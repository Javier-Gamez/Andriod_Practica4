import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';

String humanSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String baseName(String path) => path.split(RegExp(r'[\\/]')).last;

String ext(String path) {
  final n = baseName(path);
  final i = n.lastIndexOf('.');
  return i <= 0 ? '' : n.substring(i + 1).toLowerCase();
}

enum Kind { text, json, xml, image, other }

Kind kindOf(String path) {
  switch (ext(path)) {
    case 'txt':
    case 'md':
    case 'log':
    case 'csv':
    case 'yaml':
    case 'yml':
    case 'dart':
    case 'kt':
    case 'ini':
      return Kind.text;
    case 'json':
      return Kind.json;
    case 'xml':
      return Kind.xml;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
      return Kind.image;
    default:
      return Kind.other;
  }
}

/// Metadatos: se indica explícitamente cuando un dato no está disponible
/// (dart:io no expone la fecha de creación en Android/iOS).
class Meta {
  final String name, path, mime;
  final int? size;
  final DateTime? modified, created;
  Meta(this.name, this.path, this.mime, this.size, this.modified, this.created);

  static Future<Meta> of(FileSystemEntity e) async {
    final name = baseName(e.path);
    try {
      final st = await e.stat();
      final isDir = st.type == FileSystemEntityType.directory;
      final mime = isDir
          ? 'inode/directory'
          : (lookupMimeType(e.path) ?? 'No disponible');
      return Meta(name, e.path, mime, isDir ? null : st.size, st.modified, null);
    } catch (_) {
      return Meta(name, e.path, 'No disponible', null, null, null);
    }
  }
}

Future<void> showMeta(BuildContext context, FileSystemEntity e) async {
  final m = await Meta.of(e);
  if (!context.mounted) return;
  const na = 'No disponible';
  String d(DateTime? t) => t == null ? na : t.toString().split('.').first;
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Metadatos'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Nombre', m.name),
            _row('Tamaño', m.size == null ? na : humanSize(m.size!)),
            _row('Modificado', d(m.modified)),
            _row('Creado', d(m.created)),
            _row('MIME / UTType', m.mime),
            _row('Ruta', m.path),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'))
      ],
    ),
  );
}

Widget _row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$k: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(text: v),
      ])),
    );

// ---------------------------------------------------------------------------
// Visor de texto / JSON / XML
// ---------------------------------------------------------------------------
class TextViewerPage extends StatefulWidget {
  final File file;
  const TextViewerPage(this.file, {super.key});
  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  late Future<String> _content;
  @override
  void initState() {
    super.initState();
    _content = _load();
  }

  Future<String> _load() async {
    final bytes = await widget.file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FileSystemException(
          'Archivo demasiado grande para mostrar (>5 MB)');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Widget build(BuildContext context) {
    final name = baseName(widget.file.path);
    final kind = kindOf(widget.file.path);
    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis), actions: [
        IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showMeta(context, widget.file)),
      ]),
      body: FutureBuilder<String>(
        future: _content,
        builder: (c, s) {
          if (s.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo leer el archivo:\n${s.error}',
                        textAlign: TextAlign.center)));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var text = s.data!;
          String? warn;
          List<InlineSpan> spans;
          final mono = TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface);
          if (kind == Kind.json) {
            try {
              text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
            } catch (e) {
              warn = 'JSON inválido: se muestra el contenido sin formato.';
            }
            spans = warn == null
                ? highlightJson(text, context)
                : [TextSpan(text: text)];
          } else if (kind == Kind.xml) {
            try {
              text = XmlDocument.parse(text)
                  .toXmlString(pretty: true, indent: '  ');
            } catch (e) {
              warn = 'XML inválido: se muestra el contenido sin formato.';
            }
            spans = warn == null
                ? highlightXml(text, context)
                : [TextSpan(text: text)];
          } else {
            spans = [TextSpan(text: text)];
          }
          return Column(children: [
            if (warn != null)
              MaterialBanner(content: Text(warn), actions: const [SizedBox()]),
            if (text.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24), child: Text('(archivo vacío)')),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                      TextSpan(style: mono, children: spans)),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Resaltado de sintaxis propio (sin dependencias) para JSON.
List<InlineSpan> highlightJson(String s, BuildContext ctx) {
  final dark = Theme.of(ctx).brightness == Brightness.dark;
  final key = dark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5);
  final str = dark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
  final nm = dark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
  final kw = dark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
  final re = RegExp(
      r'("(?:\\.|[^"\\])*")(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b');
  return _tokenize(s, re, (m) {
    if (m.group(1) != null) {
      final isKey = m.group(2) != null;
      return [
        TextSpan(text: m.group(1), style: TextStyle(color: isKey ? key : str)),
        if (isKey) TextSpan(text: m.group(2)),
      ];
    }
    if (m.group(3) != null) {
      return [TextSpan(text: m.group(3), style: TextStyle(color: nm))];
    }
    return [
      TextSpan(
          text: m.group(4),
          style: TextStyle(color: kw, fontWeight: FontWeight.bold))
    ];
  });
}

/// Resaltado de sintaxis para XML (comentarios, etiquetas, atributos, valores).
List<InlineSpan> highlightXml(String s, BuildContext ctx) {
  final dark = Theme.of(ctx).brightness == Brightness.dark;
  final com = dark ? const Color(0xFF6A9955) : const Color(0xFF008000);
  final tag = dark ? const Color(0xFF569CD6) : const Color(0xFF800000);
  final att = dark ? const Color(0xFF9CDCFE) : const Color(0xFFE50000);
  final val = dark ? const Color(0xFFCE9178) : const Color(0xFF0000FF);
  final re = RegExp(
      r'''(<!--[\s\S]*?-->)|(<\?[\s\S]*?\?>)|(</?)([\w:.-]+)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(/?>)''');
  final attRe = RegExp(r'''([\w:.-]+)(\s*=\s*)("[^"]*"|'[^']*')''');
  return _tokenize(s, re, (m) {
    if (m.group(1) != null) {
      return [
        TextSpan(
            text: m.group(1),
            style: TextStyle(color: com, fontStyle: FontStyle.italic))
      ];
    }
    if (m.group(2) != null) {
      return [TextSpan(text: m.group(2), style: TextStyle(color: tag))];
    }
    final out = <InlineSpan>[
      TextSpan(text: m.group(3), style: TextStyle(color: tag)),
      TextSpan(
          text: m.group(4),
          style: TextStyle(color: tag, fontWeight: FontWeight.bold)),
    ];
    out.addAll(_tokenize(
        m.group(5) ?? '',
        attRe,
        (a) => [
              TextSpan(text: a.group(1), style: TextStyle(color: att)),
              TextSpan(text: a.group(2)),
              TextSpan(text: a.group(3), style: TextStyle(color: val)),
            ]));
    out.add(TextSpan(text: m.group(6), style: TextStyle(color: tag)));
    return out;
  });
}

List<InlineSpan> _tokenize(
    String s, RegExp re, List<InlineSpan> Function(RegExpMatch) f) {
  final out = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > last) out.add(TextSpan(text: s.substring(last, m.start)));
    out.addAll(f(m));
    last = m.end;
  }
  if (last < s.length) out.add(TextSpan(text: s.substring(last)));
  return out;
}

// ---------------------------------------------------------------------------
// Visor de imágenes con zoom (InteractiveViewer) y rotación
// ---------------------------------------------------------------------------
class ImageViewerPage extends StatefulWidget {
  final File file;
  const ImageViewerPage(this.file, {super.key});
  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  int quarter = 0;
  final tc = TransformationController();

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = baseName(widget.file.path);
    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis), actions: [
        IconButton(
            tooltip: 'Girar izquierda',
            icon: const Icon(Icons.rotate_left),
            onPressed: () => setState(() => quarter = (quarter + 3) % 4)),
        IconButton(
            tooltip: 'Girar derecha',
            icon: const Icon(Icons.rotate_right),
            onPressed: () => setState(() => quarter = (quarter + 1) % 4)),
        IconButton(
            tooltip: 'Restablecer',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () => setState(() {
                  quarter = 0;
                  tc.value = Matrix4.identity();
                })),
        IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showMeta(context, widget.file)),
      ]),
      body: InteractiveViewer(
        transformationController: tc,
        minScale: 0.5,
        maxScale: 8,
        child: Center(
          child: Transform.rotate(
            angle: quarter * math.pi / 2,
            child: Image.file(widget.file,
                errorBuilder: (_, e, __) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No se pudo decodificar la imagen (archivo corrupto o formato no soportado).'))),
          ),
        ),
      ),
    );
  }
}
