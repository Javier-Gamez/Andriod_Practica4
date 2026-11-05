import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';
import 'model.dart';
import 'theme.dart';

void snack(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

// ===========================================================================
// Menú principal
// ===========================================================================
class MenuPage extends StatefulWidget {
  const MenuPage({super.key});
  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  GameState? resumable;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final g = await store.latest();
    if (mounted) setState(() => resumable = g);
  }

  Future<void> _play(GameState g) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GamePage(g)));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const SizedBox(height: 12),
              Icon(Icons.lightbulb, size: 72, color: cs.primary),
              Text('APAGÓN', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
              const Text('Apaga todas las luces. Cada toque invierte la celda y sus vecinas.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: store,
                builder: (context, child) => Text('Puntos totales: ${store.totalScore} · Victorias: ${store.gamesWon}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 20),
              if (resumable != null)
                FilledButton.icon(
                  onPressed: () => _play(resumable!),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continuar: ${resumable!.name} (${resumable!.moves.length} mov.)'),
                ),
              const SizedBox(height: 10),
              for (final l in levels)
                ListenableBuilder(
                  listenable: store,
                  builder: (context, child) {
                    final locked = l.id > store.unlockedLevel;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FilledButton.tonalIcon(
                        onPressed: locked
                            ? () => snack(context, 'Gana el nivel anterior para desbloquear.')
                            : () => _play(GameState.newGame(l, palette: store.palette.name, sound: store.sound, haptics: store.haptics)..showCounter = store.showCounter),
                        icon: Icon(locked ? Icons.lock : Icons.grid_view),
                        label: Text(l.name),
                      ),
                    );
                  },
                ),
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const SavesPage()));
                  _refresh();
                },
                icon: const Icon(Icons.folder_copy_outlined),
                label: const Text('Partidas guardadas'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OptionsPage())),
                icon: const Icon(Icons.settings),
                label: const Text('Opciones'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Partida
// ===========================================================================
class GamePage extends StatefulWidget {
  final GameState game;
  const GamePage(this.game, {super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late GameState g = widget.game;
  Timer? timer;
  bool dirty = false;
  int? lastTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    timer?.cancel();
    if (g.solved) return;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => g.elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Autoguardado al pasar a segundo plano => la partida se recupera aunque
  /// el sistema cierre la app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      timer?.cancel();
      _autosave();
    } else if (s == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  Future<void> _autosave() async {
    if (g.solved) return;
    try {
      await store.save(g);
      dirty = false;
    } catch (_) {}
  }

  void _tap(int i) {
    if (g.solved) return;
    setState(() {
      g.toggle(i);
      lastTap = i;
      dirty = true;
    });
    if (g.sound) SystemSound.play(SystemSoundType.click);
    if (g.haptics) HapticFeedback.selectionClick();
    if (g.solved) _win();
  }

  Future<void> _win() async {
    timer?.cancel();
    g.score = g.computeScore();
    if (g.sound) SystemSound.play(SystemSoundType.alert);
    if (g.haptics) HapticFeedback.heavyImpact();
    await store.registerWin(g);
    await store.save(g);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        icon: const Icon(Icons.emoji_events, size: 48, color: Colors.amber),
        title: const Text('¡Nivel completado!'),
        content: Text('Puntos: ${g.score}\nMovimientos: ${g.moves.length}\nTiempo: ${_fmt(g.elapsedSeconds)}'
            '${g.levelId < levels.length ? '\n\nSe desbloqueó el siguiente nivel.' : ''}'),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Genial'))],
      ),
    );
  }

  void _undo() {
    if (g.moves.isEmpty || g.solved) return;
    // Un toque es su propio inverso: repetirlo deshace el movimiento.
    final last = g.moves.last;
    setState(() {
      g.toggle(last);
      g.moves.removeLast(); // quita el toque de deshacer
      g.moves.removeLast(); // quita el movimiento original
      lastTap = last;
    });
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _saveDialog() async {
    final nameC = TextEditingController(text: g.name);
    final tagC = TextEditingController(text: g.tag);
    var fmt = store.format;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setD) => AlertDialog(
          title: const Text('Guardar partida'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: tagC, decoration: const InputDecoration(labelText: 'Etiqueta (p. ej. Práctica, Récord)')),
            const SizedBox(height: 12),
            SegmentedButton<SaveFormat>(
              segments: [for (final f in SaveFormat.values) ButtonSegment(value: f, label: Text('.${f.name}'))],
              selected: {fmt},
              onSelectionChanged: (s) => setD(() => fmt = s.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    g.name = nameC.text.trim().replaceAll(RegExp(r'[\r\n]'), ' ').isEmpty ? 'Partida' : nameC.text.trim().replaceAll(RegExp(r'[\r\n]'), ' ');
    g.tag = tagC.text.trim().replaceAll(RegExp(r'[\r\n]'), ' ').isEmpty ? 'General' : tagC.text.trim().replaceAll(RegExp(r'[\r\n]'), ' ');
    try {
      final f = await store.save(g, as: fmt);
      dirty = false;
      snack(context, 'Guardada: ${f.path.split(RegExp(r'[\\/]')).last}');
    } on FileSystemException catch (e) {
      snack(context, 'No se pudo guardar (${e.osError?.errorCode == 28 ? 'almacenamiento insuficiente' : e.message}).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final board = AspectRatio(
      aspectRatio: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: g.size, mainAxisSpacing: 8, crossAxisSpacing: 8),
          itemCount: g.board.length,
          itemBuilder: (context, i) {
            final on = g.board[i];
            return GestureDetector(
              onTap: () => _tap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                transform: Matrix4.identity()..scale(lastTap == i ? 0.92 : 1.0),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: on ? cs.primary : cs.surfaceContainerHighest,
                  boxShadow: on ? [BoxShadow(color: cs.primary.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 2)] : [],
                ),
                child: Icon(on ? Icons.lightbulb : Icons.lightbulb_outline, color: on ? cs.onPrimary : cs.outline),
              ),
            );
          },
        ),
      ),
    );
    final info = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(g.level.name, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 16, children: [
        Chip(avatar: const Icon(Icons.timer, size: 18), label: Text(_fmt(g.elapsedSeconds))),
        if (g.showCounter) Chip(avatar: const Icon(Icons.touch_app, size: 18), label: Text('${g.moves.length} mov.')),
        Chip(avatar: const Icon(Icons.star, size: 18), label: Text('${g.solved ? g.score : g.computeScore()} pts')),
      ]),
      const SizedBox(height: 8),
      Text('Luces encendidas: ${g.board.where((e) => e).length}'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: g.moves.isEmpty ? null : _undo, icon: const Icon(Icons.undo), label: const Text('Deshacer')),
        FilledButton.icon(onPressed: _saveDialog, icon: const Icon(Icons.save), label: const Text('Guardar')),
      ]),
    ]);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, r) {
        if (didPop && dirty && !g.solved) _autosave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(g.name)),
        body: SafeArea(
          child: OrientationBuilder(
            builder: (context, o) => o == Orientation.landscape
                ? Row(children: [Expanded(child: Center(child: board)), Expanded(child: info)])
                : Column(children: [Expanded(flex: 3, child: Center(child: board)), Expanded(flex: 2, child: info)]),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Partidas guardadas: lista con metadatos, etiquetas, ver, exportar, importar
// ===========================================================================
class SavesPage extends StatefulWidget {
  const SavesPage({super.key});
  @override
  State<SavesPage> createState() => _SavesPageState();
}

class _SavesPageState extends State<SavesPage> {
  late Future<List<SaveEntry>> fut = store.list();
  String filter = 'Todas';

  void _reload() => setState(() => fut = store.list());

  Future<void> _open(SaveEntry e) async {
    if (e.state == null) return snack(context, 'Archivo dañado: ${e.error}');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GamePage(e.state!)));
    _reload();
  }

  Future<void> _view(SaveEntry e) async {
    String text;
    try {
      text = await e.file.readAsString();
    } catch (err) {
      text = 'No se pudo leer: $err';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(e.fileName, style: const TextStyle(fontSize: 14)),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: SelectableText(text.isEmpty ? '(archivo vacío)' : text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)))),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _export(SaveEntry e) async {
    try {
      final uri = await FilePicker.saveFile(fileName: e.fileName, bytes: await e.file.readAsBytes());
      snack(context, uri == null ? 'Exportación cancelada.' : 'Partida exportada.');
    } catch (err) {
      snack(context, 'No se pudo exportar: $err');
    }
  }

  Future<void> _share(SaveEntry e) async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(e.file.path)]));
    } catch (err) {
      snack(context, 'No se pudo compartir: $err');
    }
  }

  Future<void> _delete(SaveEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Eliminar partida'),
        content: Text('¿Eliminar "${e.fileName}"? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await e.file.delete();
      snack(context, 'Partida eliminada.');
    } catch (err) {
      snack(context, 'No se pudo eliminar: $err');
    }
    _reload();
  }

  Future<void> _retag(SaveEntry e) async {
    final c = TextEditingController(text: e.state!.tag);
    final r = await showDialog<String>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Etiquetar partida'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Etiqueta')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dc, c.text.trim()), child: const Text('Aplicar')),
        ],
      ),
    );
    if (r == null || r.isEmpty) return;
    e.state!.tag = r.replaceAll(RegExp(r'[\r\n]'), ' ');
    final f = SaveFormat.values.firstWhere((x) => x.name == e.ext);
    await store.save(e.state!, as: f);
    _reload();
  }

  /// Importa una partida desde cualquier ubicación con el selector del sistema.
  Future<void> _import() async {
    try {
      final pf = await FilePicker.pickFile();
      if (pf == null || pf.path == null) return snack(context, 'Importación cancelada.');
      final ext = pf.path!.split('.').last.toLowerCase();
      final g = GameState.parse(await File(pf.path!).readAsString(), ext); // valida antes de copiar
      g.id = '${g.id}_imp${DateTime.now().millisecondsSinceEpoch % 10000}';
      await store.save(g, as: SaveFormat.values.firstWhere((x) => x.name == ext));
      snack(context, 'Partida importada: ${g.name}');
      _reload();
    } on SaveFormatError catch (e) {
      snack(context, 'No se pudo importar: $e');
    } catch (e) {
      snack(context, 'No se pudo importar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partidas guardadas'), actions: [
        IconButton(tooltip: 'Importar', icon: const Icon(Icons.file_open), onPressed: _import),
        IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: _reload),
      ]),
      body: FutureBuilder<List<SaveEntry>>(
        future: fut,
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final all = s.data!;
          if (all.isEmpty) return const Center(child: Text('No hay partidas guardadas.'));
          final tags = {'Todas', ...all.where((e) => e.state != null).map((e) => e.state!.tag)};
          final shown = all.where((e) => filter == 'Todas' || e.state?.tag == filter).toList();
          return Column(children: [
            SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
                for (final t in tags)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t), selected: filter == t, onSelected: (_) => setState(() => filter = t))),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final e = shown[i];
                  final g = e.state;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: Icon(g == null ? Icons.error_outline : (g.solved ? Icons.check_circle : Icons.pending_outlined), color: g == null ? Colors.red : null),
                      title: Text(g?.name ?? e.fileName),
                      subtitle: Text(g == null
                          ? 'Dañada: ${e.error}'
                          : '${g.level.name}\n${e.fileName} · ${(e.bytes / 1024).toStringAsFixed(1)} KB · ${e.modified.toString().split('.').first}\n'
                              'Puntos ${g.score} · ${g.moves.length} mov. · ${g.elapsedSeconds}s · #${g.tag}'),
                      isThreeLine: true,
                      onTap: () => _open(e),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          switch (v) {
                            case 'view': _view(e);
                            case 'tag': _retag(e);
                            case 'export': _export(e);
                            case 'share': _share(e);
                            case 'del': _delete(e);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('Ver contenido')),
                          if (g != null) const PopupMenuItem(value: 'tag', child: Text('Cambiar etiqueta')),
                          const PopupMenuItem(value: 'export', child: Text('Exportar a...')),
                          const PopupMenuItem(value: 'share', child: Text('Compartir')),
                          const PopupMenuItem(value: 'del', child: Text('Eliminar')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ===========================================================================
// Opciones
// ===========================================================================
class OptionsPage extends StatelessWidget {
  const OptionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Opciones')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Formato de guardado', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<SaveFormat>(
            segments: [for (final f in SaveFormat.values) ButtonSegment(value: f, label: Text('.${f.name}'))],
            selected: {store.format},
            onSelectionChanged: (s) => store.setOpt(f: s.first),
          ),
          const Divider(height: 32),
          const Text('Tema', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final p in AppPalette.values)
            RadioListTile<AppPalette>(
              value: p,
              groupValue: store.palette,
              onChanged: (v) => store.setOpt(p: v),
              title: Text(p.label),
              secondary: CircleAvatar(backgroundColor: p.seed, radius: 12),
            ),
          const Text('El modo claro/oscuro sigue al sistema.', style: TextStyle(fontSize: 12)),
          const Divider(height: 32),
          const Text('Jugabilidad', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(title: const Text('Sonido'), value: store.sound, onChanged: (v) => store.setOpt(s: v)),
          SwitchListTile(title: const Text('Vibración'), value: store.haptics, onChanged: (v) => store.setOpt(h: v)),
          SwitchListTile(title: const Text('Mostrar contador de movimientos'), value: store.showCounter, onChanged: (v) => store.setOpt(c: v)),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('Gestionar partidas guardadas'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavesPage())),
          ),
        ]),
      ),
    );
  }
}
