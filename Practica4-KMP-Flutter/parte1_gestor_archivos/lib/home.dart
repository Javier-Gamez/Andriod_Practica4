import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';
import 'storage.dart';
import 'theme.dart';
import 'viewers.dart';

void snack(BuildContext c, String msg) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext c, String title, String body) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aceptar')),
      ],
    ),
  );
  return r ?? false;
}

/// Abre un archivo según su tipo; formatos no soportados -> diálogo con
/// opciones abrir / compartir / exportar.
Future<void> openFile(BuildContext context, File f) async {
  if (!await f.exists()) {
    snack(context, 'El archivo ya no existe o la ruta no está disponible.');
    return;
  }
  await prefs.addRecent(f.path);
  if (!context.mounted) return;
  switch (kindOf(f.path)) {
    case Kind.text:
    case Kind.json:
    case Kind.xml:
      Navigator.push(context, MaterialPageRoute(builder: (_) => TextViewerPage(f)));
    case Kind.image:
      Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewerPage(f)));
    case Kind.other:
      showUnsupportedDialog(context, f);
  }
}

void showUnsupportedDialog(BuildContext context, File f) {
  showDialog(
    context: context,
    builder: (dc) => AlertDialog(
      title: const Text('Formato no soportado'),
      content: Text('"${baseName(f.path)}" no se puede visualizar dentro de la app. '
          '¿Qué deseas hacer?'),
      actions: [
        TextButton(
            onPressed: () async {
              Navigator.pop(dc);
              final r = await OpenFilex.open(f.path);
              if (r.type != ResultType.done && context.mounted) {
                snack(context, 'No hay app que abra este archivo (${r.message}).');
              }
            },
            child: const Text('Abrir con...')),
        TextButton(
            onPressed: () async {
              Navigator.pop(dc);
              await shareFile(context, f);
            },
            child: const Text('Compartir')),
        TextButton(
            onPressed: () async {
              Navigator.pop(dc);
              await exportFile(context, f);
            },
            child: const Text('Exportar')),
      ],
    ),
  );
}

Future<void> shareFile(BuildContext context, File f) async {
  try {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
  } catch (e) {
    snack(context, 'No se pudo compartir: $e');
  }
}

/// Exporta con el selector del sistema (SAF "Crear documento" / Files en iOS).
Future<void> exportFile(BuildContext context, File f) async {
  try {
    final bytes = await f.readAsBytes();
    final uri = await FilePicker.saveFile(fileName: baseName(f.path), bytes: bytes);
    if (!context.mounted) return;
    snack(context, uri == null ? 'Exportación cancelada.' : 'Archivo exportado correctamente.');
  } catch (e) {
    snack(context, 'No se pudo exportar: $e');
  }
}

// ===========================================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  static const _titles = ['Explorar', 'Recientes', 'Favoritos', 'Ajustes'];
  static const _icons = [Icons.folder_open, Icons.history, Icons.star_outline, Icons.palette_outlined];

  @override
  Widget build(BuildContext context) {
    final pages = [const RootsTab(), const RecentsTab(favorites: false), const RecentsTab(favorites: true), const SettingsTab()];
    // Diseño responsivo: NavigationRail en pantallas anchas / horizontal,
    // NavigationBar inferior en pantallas angostas.
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final body = pages[tab];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[tab])),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: tab,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: [for (var i = 0; i < 4; i++) NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_titles[i]))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [for (var i = 0; i < 4; i++) NavigationDestination(icon: Icon(_icons[i]), label: _titles[i])],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Raíces: espacio propio + carpetas autorizadas + archivos del selector
// ---------------------------------------------------------------------------
class RootsTab extends StatelessWidget {
  const RootsTab({super.key});

  Future<void> _pickFolder(BuildContext context) async {
    final ok = await confirm(context, 'Acceso a una carpeta',
        'Se abrirá el selector del sistema para que elijas una carpeta. La app sólo podrá ver lo que autorices y no pedimos acceso global al almacenamiento.');
    if (!ok) return;
    try {
      final p = await FilePicker.getDirectoryPath();
      if (p == null) {
        if (context.mounted) snack(context, 'No se autorizó ninguna carpeta.');
        return;
      }
      await prefs.addRoot(p);
      if (context.mounted) snack(context, 'Carpeta autorizada.');
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo abrir el selector: $e');
    }
  }

  Future<void> _pickFiles(BuildContext context) async {
    final ok = await confirm(context, 'Abrir archivos',
        'Elige uno o varios documentos con el selector del sistema (SAF en Android, Files en iOS). Se abrirá una copia de lectura.');
    if (!ok) return;
    try {
      final res = await FilePicker.pickFiles();
      if (res.isEmpty) {
        if (context.mounted) snack(context, 'Selección cancelada.');
        return;
      }
      final files = res.where((f) => f.path != null).map((f) => File(f.path!)).toList();
      if (!context.mounted || files.isEmpty) return;
      if (files.length == 1) {
        await openFile(context, files.first);
      } else {
        for (final f in files) {
          await prefs.addRecent(f.path);
        }
        if (context.mounted) snack(context, '${files.length} archivos agregados a Recientes.');
      }
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo leer la selección: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, __) => ListView(children: [
        FutureBuilder<List<Directory>>(
          future: Future.wait([getApplicationDocumentsDirectory(), getTemporaryDirectory()]),
          builder: (_, s) {
            if (!s.hasData) return const LinearProgressIndicator();
            return Column(children: [
              ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Espacio de la aplicación'),
                  subtitle: const Text('Documentos privados de la app'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserPage(root: s.data![0].path, title: 'Espacio de la app')))),
              ListTile(
                  leading: const Icon(Icons.cached),
                  title: const Text('Caché (archivos abiertos con el selector)'),
                  subtitle: const Text('Copias temporales de la app'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserPage(root: s.data![1].path, title: 'Caché')))),
            ]);
          },
        ),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Carpetas autorizadas', style: TextStyle(fontWeight: FontWeight.bold))),
        if (prefs.authorizedRoots.isEmpty)
          const ListTile(title: Text('Ninguna todavía. Usa "Elegir carpeta".')),
        for (final r in prefs.authorizedRoots)
          ListTile(
            leading: const Icon(Icons.folder_shared),
            title: Text(baseName(r)),
            subtitle: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
                tooltip: 'Quitar autorización',
                icon: const Icon(Icons.link_off),
                onPressed: () => prefs.removeRoot(r)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserPage(root: r, title: baseName(r)))),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _pickFolder(context), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Elegir carpeta')),
            FilledButton.tonalIcon(onPressed: () => _pickFiles(context), icon: const Icon(Icons.file_open_outlined), label: const Text('Abrir archivo(s)')),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Recientes / Favoritos (persistentes con SharedPreferences)
// ---------------------------------------------------------------------------
class RecentsTab extends StatelessWidget {
  final bool favorites;
  const RecentsTab({super.key, required this.favorites});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, __) {
        final items = favorites ? prefs.favorites : prefs.recents;
        if (items.isEmpty) {
          return Center(child: Text(favorites ? 'Aún no hay favoritos.\nMarca ⭐ desde el menú de un archivo.' : 'Aún no hay archivos recientes.', textAlign: TextAlign.center));
        }
        return Column(children: [
          if (!favorites)
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: prefs.clearRecents, icon: const Icon(Icons.delete_sweep), label: const Text('Limpiar'))),
          Expanded(
            child: ListView(children: [
              for (final p in items)
                ListTile(
                  leading: Icon(iconFor(p)),
                  title: Text(baseName(p)),
                  subtitle: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: favorites ? IconButton(icon: const Icon(Icons.star), onPressed: () => prefs.toggleFav(p)) : null,
                  onTap: () => openFile(context, File(p)),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

IconData iconFor(String path) => switch (kindOf(path)) {
      Kind.text => Icons.description_outlined,
      Kind.json => Icons.data_object,
      Kind.xml => Icons.code,
      Kind.image => Icons.image_outlined,
      Kind.other => Icons.insert_drive_file_outlined,
    };

// ---------------------------------------------------------------------------
// Ajustes: temas
// ---------------------------------------------------------------------------
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, __) => ListView(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Tema de color (el modo claro/oscuro sigue al sistema)')),
        for (final p in AppPalette.values)
          RadioListTile<AppPalette>(
            value: p,
            groupValue: prefs.palette,
            onChanged: (v) => prefs.setPalette(v!),
            title: Text(p.label),
            secondary: CircleAvatar(backgroundColor: p.seed, radius: 12),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Vaciar caché de miniaturas'),
          onTap: () async {
            await ThumbCache.clear();
            if (context.mounted) snack(context, 'Caché de miniaturas eliminada.');
          },
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Funciona 100% sin conexión'),
          subtitle: Text('Android 7.0+ (API 24) / iOS 15+'),
        ),
      ]),
    );
  }
}

// ===========================================================================
// Navegador de directorios con breadcrumbs y operaciones de archivo
// ===========================================================================
class BrowserPage extends StatefulWidget {
  final String root, title;
  const BrowserPage({super.key, required this.root, required this.title});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late String cwd = widget.root;
  List<FileSystemEntity> items = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = Directory(cwd);
      if (!await d.exists()) throw const FileSystemException('La ruta ya no está disponible');
      final l = await d.list().toList();
      l.sort((a, b) {
        final ad = a is Directory, bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return baseName(a.path).toLowerCase().compareTo(baseName(b.path).toLowerCase());
      });
      items = l.where((e) => !baseName(e.path).startsWith('.')).toList();
      error = null;
    } catch (e) {
      items = [];
      error = 'No se pudo listar la carpeta (¿permiso revocado o ruta inexistente?)\n$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _go(String p) {
    cwd = p;
    _load();
  }

  List<String> get _crumbs {
    final rel = cwd.length > widget.root.length ? cwd.substring(widget.root.length) : '';
    return rel.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  }

  Widget _breadcrumbs() {
    final parts = _crumbs;
    var acc = widget.root;
    final sep = Platform.pathSeparator;
    final chips = <Widget>[
      ActionChip(avatar: const Icon(Icons.home, size: 16), label: Text(widget.title), onPressed: () => _go(widget.root)),
    ];
    for (final p in parts) {
      acc = '$acc$sep$p';
      final target = acc;
      chips.add(const Icon(Icons.chevron_right, size: 18));
      chips.add(ActionChip(label: Text(p), onPressed: () => _go(target)));
    }
    return SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [for (final c in chips) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Center(child: c))]));
  }

  /// Valida que se pueda escribir en un destino antes de operar.
  Future<bool> _writable(String dir) async {
    try {
      final probe = File('$dir${Platform.pathSeparator}.probe_${DateTime.now().microsecondsSinceEpoch}');
      await probe.writeAsString('x');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _newFolder() async {
    final name = await _askName('Nueva carpeta', '');
    if (name == null) return;
    if (!await _writable(cwd)) return snack(context, 'Operación no permitida: no hay permiso de escritura aquí.');
    try {
      await Directory('$cwd${Platform.pathSeparator}$name').create();
      snack(context, 'Carpeta creada.');
    } catch (e) {
      snack(context, 'No se pudo crear: $e');
    }
    _load();
  }

  Future<String?> _askName(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dc, c.text.trim()), child: const Text('Aceptar')),
        ],
      ),
    );
    if (r == null || r.isEmpty) return null;
    if (r.contains(RegExp(r'[\\/:*?"<>|]'))) {
      if (mounted) snack(context, 'Nombre inválido (no uses \\ / : * ? " < > |).');
      return null;
    }
    return r;
  }

  Future<void> _rename(FileSystemEntity e) async {
    final n = await _askName('Renombrar', baseName(e.path));
    if (n == null) return;
    final dest = '${e.parent.path}${Platform.pathSeparator}$n';
    if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) return snack(context, 'Ya existe un elemento con ese nombre.');
    try {
      await e.rename(dest);
      await prefs.replacePath(e.path, dest);
      snack(context, 'Renombrado.');
    } catch (err) {
      snack(context, 'No se pudo renombrar: $err');
    }
    _load();
  }

  Future<void> _delete(FileSystemEntity e) async {
    if (!await confirm(context, 'Eliminar', '¿Eliminar "${baseName(e.path)}"? Esta acción no se puede deshacer.')) return;
    try {
      await e.delete(recursive: true);
      await prefs.replacePath(e.path, null);
      snack(context, 'Eliminado.');
    } on FileSystemException catch (err) {
      snack(context, 'Operación no permitida: ${err.osError?.message ?? err.message}');
    }
    _load();
  }

  Future<void> _copyMove(FileSystemEntity e, {required bool move}) async {
    final dest = await showDialog<String>(context: context, builder: (_) => DestPicker(startAt: widget.root, root: widget.root));
    if (dest == null) return;
    if (!await _writable(dest)) return snack(context, 'Operación no permitida: el destino no es escribible.');
    final target = '$dest${Platform.pathSeparator}${baseName(e.path)}';
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) return snack(context, 'Ya existe "${baseName(e.path)}" en el destino.');
    if (e is Directory) return snack(context, 'Por ahora sólo se copian/mueven archivos, no carpetas.');
    try {
      final f = e as File;
      final size = await f.length();
      if (move) {
        try {
          await f.rename(target);
        } on FileSystemException {
          await f.copy(target); // rename falla entre volúmenes distintos
          await f.delete();
        }
        await prefs.replacePath(f.path, target);
      } else {
        await f.copy(target);
      }
      snack(context, '${move ? 'Movido' : 'Copiado'} (${humanSize(size)}).');
    } on FileSystemException catch (err) {
      final full = (err.osError?.errorCode == 28);
      snack(context, full ? 'Almacenamiento insuficiente.' : 'No se pudo completar: ${err.osError?.message ?? err.message}');
    }
    _load();
  }

  Future<void> _importHere() async {
    try {
      final res = await FilePicker.pickFiles();
      if (res.isEmpty) return snack(context, 'Selección cancelada.');
      if (!await _writable(cwd)) return snack(context, 'Operación no permitida: carpeta sin escritura.');
      var n = 0;
      for (final pf in res) {
        if (pf.path == null) continue;
        final t = '$cwd${Platform.pathSeparator}${pf.name}';
        if (await File(t).exists()) continue;
        await File(pf.path!).copy(t);
        n++;
      }
      snack(context, '$n archivo(s) importado(s).');
    } catch (e) {
      snack(context, 'Importación fallida: $e');
    }
    _load();
  }

  void _menu(FileSystemEntity e) {
    final isFile = e is File;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (bc) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isFile) _mi(bc, Icons.open_in_new, 'Abrir', () => openFile(context, e)),
            _mi(bc, Icons.info_outline, 'Metadatos', () => showMeta(context, e)),
            if (isFile) _mi(bc, prefs.isFav(e.path) ? Icons.star : Icons.star_outline, prefs.isFav(e.path) ? 'Quitar de favoritos' : 'Agregar a favoritos', () => prefs.toggleFav(e.path)),
            _mi(bc, Icons.drive_file_rename_outline, 'Renombrar', () => _rename(e)),
            if (isFile) _mi(bc, Icons.copy, 'Copiar a...', () => _copyMove(e, move: false)),
            if (isFile) _mi(bc, Icons.drive_file_move_outline, 'Mover a...', () => _copyMove(e, move: true)),
            if (isFile) _mi(bc, Icons.share, 'Compartir', () => shareFile(context, e)),
            if (isFile) _mi(bc, Icons.ios_share, 'Exportar...', () => exportFile(context, e)),
            _mi(bc, Icons.delete_outline, 'Eliminar', () => _delete(e)),
          ]),
        ),
      ),
    );
  }

  Widget _mi(BuildContext bc, IconData i, String t, VoidCallback f) => ListTile(leading: Icon(i), title: Text(t), onTap: () {
        Navigator.pop(bc);
        f();
      });

  @override
  Widget build(BuildContext context) {
    final atRoot = cwd == widget.root;
    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(Directory(cwd).parent.path);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [
          IconButton(tooltip: 'Nueva carpeta', icon: const Icon(Icons.create_new_folder_outlined), onPressed: _newFolder),
          IconButton(tooltip: 'Importar archivos aquí', icon: const Icon(Icons.file_download_outlined), onPressed: _importHere),
          IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
        body: Column(children: [
          _breadcrumbs(),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center)))
                    : items.isEmpty
                        ? const Center(child: Text('Carpeta vacía'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, i) => _tile(items[i]),
                            ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(FileSystemEntity e) {
    final isDir = e is Directory;
    return ListTile(
      leading: isDir
          ? const Icon(Icons.folder, size: 36)
          : kindOf(e.path) == Kind.image
              ? Thumb(File(e.path))
              : Icon(iconFor(e.path), size: 36),
      title: Text(baseName(e.path), overflow: TextOverflow.ellipsis),
      subtitle: isDir
          ? const Text('Carpeta')
          : FutureBuilder<Meta>(
              future: Meta.of(e),
              builder: (_, s) => Text(s.hasData ? '${s.data!.size == null ? 'Tamaño no disponible' : humanSize(s.data!.size!)} · ${s.data!.modified?.toString().split('.').first ?? 'Fecha no disponible'}' : '...'),
            ),
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _menu(e)),
      onTap: () => isDir ? _go(e.path) : openFile(context, e as File),
      onLongPress: () => _menu(e),
    );
  }
}

/// Miniatura con caché en memoria y disco.
class Thumb extends StatelessWidget {
  final File file;
  const Thumb(this.file, {super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: FutureBuilder(
        future: ThumbCache.get(file),
        builder: (_, s) => s.data == null
            ? const Icon(Icons.image_outlined, size: 36)
            : ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true)),
      ),
    );
  }
}

/// Selector de carpeta destino, limitado a la raíz autorizada.
class DestPicker extends StatefulWidget {
  final String startAt, root;
  const DestPicker({super.key, required this.startAt, required this.root});
  @override
  State<DestPicker> createState() => _DestPickerState();
}

class _DestPickerState extends State<DestPicker> {
  late String cur = widget.startAt;
  @override
  Widget build(BuildContext context) {
    List<Directory> dirs;
    try {
      dirs = Directory(cur).listSync().whereType<Directory>().where((d) => !baseName(d.path).startsWith('.')).toList();
    } catch (_) {
      dirs = [];
    }
    return AlertDialog(
      title: const Text('Elegir carpeta destino'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(children: [
          Text(cur, style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: ListView(children: [
              if (cur != widget.root)
                ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('..'), onTap: () => setState(() => cur = Directory(cur).parent.path)),
              for (final d in dirs) ListTile(leading: const Icon(Icons.folder), title: Text(baseName(d.path)), onTap: () => setState(() => cur = d.path)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, cur), child: const Text('Seleccionar aquí')),
      ],
    );
  }
}
