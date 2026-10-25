import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../services/extract.dart';
import '../services/library.dart';
import 'reader_screen.dart';
import 'voice_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _importing = false;

  Library get _library => widget.state.library;

  @override
  void initState() {
    super.initState();
    widget.state.listenForShares(
      (path) =>
          _import(p.basename(path), File(path).openRead(), deleteAfter: path),
    );
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Choose a document');
    if (files.isEmpty) return;
    final f = files.first;
    await _import(f.name, f.readAsByteStream());
  }

  Future<void> _import(
    String name,
    Stream<List<int>> bytes, {
    String? deleteAfter,
  }) async {
    setState(() => _importing = true);
    try {
      final doc = await _library.import(name, bytes);
      if (!mounted) return;
      setState(() {});
      await _openDoc(doc, autoplay: true);
    } on ExtractException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Couldn\'t open "$name": $e');
    } finally {
      if (deleteAfter != null) File(deleteAfter).delete().ignore();
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openDoc(Doc d, {bool autoplay = false}) async {
    final h = widget.state.handler;
    if (h.doc?.id != d.id) {
      await h.open(d, await _library.segmentsFor(d));
      if (autoplay) await h.play();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(state: widget.state)),
    );
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmRemove(Doc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          '"${d.title}" will be removed from Earshot. The original file isn\'t touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final h = widget.state.handler;
    if (h.doc?.id == d.id) await h.pause();
    await _library.remove(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final docs = _library.docs;
    final h = widget.state.handler;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earshot'),
        actions: [
          IconButton(
            tooltip: 'Voice and speed',
            icon: const Icon(Icons.record_voice_over),
            onPressed: () => showVoiceSheet(context, h),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _pick,
        icon: _importing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'Opening…' : 'Open document'),
      ),
      body: docs.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = docs[i];
                final current = h.doc?.id == d.id;
                return ListTile(
                  leading: Icon(_iconFor(d.filePath)),
                  title: Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(value: d.progress),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          d.position >= d.total && d.total > 0
                              ? 'Finished'
                              : '${(d.progress * 100).round()}%',
                        ),
                      ],
                    ),
                  ),
                  trailing: current
                      ? ValueListenableBuilder<bool>(
                          valueListenable: h.playing,
                          builder: (_, playing, _) =>
                              Icon(playing ? Icons.graphic_eq : Icons.pause),
                        )
                      : null,
                  onTap: () => _openDoc(d),
                  onLongPress: () => _confirmRemove(d),
                );
              },
            ),
    );
  }

  IconData _iconFor(String path) => switch (p.extension(path).toLowerCase()) {
    '.pdf' => Icons.picture_as_pdf_outlined,
    '.docx' => Icons.description_outlined,
    _ => Icons.article_outlined,
  };
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('Nothing to read yet', style: t.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Tap "Open document" to pick a PDF, Word, text or Markdown file.\n\n'
              'From another app, use Share and choose Earshot. '
              'For a Google Doc: Share & export → Send a copy → Word or PDF.',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
