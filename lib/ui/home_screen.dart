/// Library: your documents, newest first, with a "now playing" bar docked
/// at the bottom so playback is one tap away.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../audio/reader_handler.dart';
import '../services/extract.dart';
import '../services/library.dart';
import 'player_screen.dart';
import 'theme.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

enum _Filter {
  all('All'),
  inProgress('In progress'),
  fresh('New'),
  storyteller('Storyteller'),
  finished('Finished');

  const _Filter(this.label);
  final String label;

  bool matches(Doc d) => switch (this) {
    _Filter.all => true,
    _Filter.inProgress => d.started,
    _Filter.fresh => d.position == 0,
    _Filter.storyteller => d.recorded,
    _Filter.finished => d.finished,
  };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _importing = false;
  _Filter _filter = _Filter.all;

  Library get _library => widget.state.library;
  ReaderHandler get h => widget.state.handler;

  @override
  void initState() {
    super.initState();
    widget.state.lastCrash().then((report) {
      if (report != null && mounted) _showCrash(report);
    });
    widget.state.listenForShares(
      (path) =>
          _import(p.basename(path), File(path).openRead(), deleteAfter: path),
    );
    h.index.addListener(_refresh);
    h.docVersion.addListener(_refresh);
  }

  @override
  void dispose() {
    h.index.removeListener(_refresh);
    h.docVersion.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
      setState(() => _filter = _Filter.all);
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
    if (h.doc?.id != d.id) {
      await h.open(d, await _library.segmentsFor(d));
      if (autoplay) await h.play();
    }
    if (!mounted) return;
    await _openPlayer();
  }

  Future<void> _openPlayer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(state: widget.state)),
    );
    _refresh();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showCrash(String report) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Earshot closed unexpectedly last time'),
      content: SingleChildScrollView(
        child: SelectableText(report, style: const TextStyle(fontSize: 12)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: report));
            Navigator.pop(c);
            _snack('Copied. Paste it to Claude.');
          },
        ),
      ],
    ),
  );

  Future<void> _confirmRemove(Doc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove from Earshot?'),
        content: Text(
          '"${d.title}" will be removed from your library. The original file isn\'t touched.',
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
    if (h.doc?.id == d.id) await h.pause();
    await _library.remove(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final docs = _library.docs.where(_filter.matches).toList();
    final hasPlayer = h.doc != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: libraryMaxWidth),
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Library',
                                style: ui(
                                  30,
                                  weight: 800,
                                  spacing: -0.6,
                                  color: c.text,
                                ),
                              ),
                            ),
                            RoundButton(
                              icon: Icons.tune_rounded,
                              label: 'Voice and pace',
                              onPressed: () async {
                                await showVoiceSheet(context, h);
                                _refresh();
                              },
                            ),
                            const SizedBox(width: 8),
                            _importing
                                ? const SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Padding(
                                      padding: EdgeInsets.all(11),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  )
                                : RoundButton(
                                    icon: Icons.add_rounded,
                                    label: 'Add a document',
                                    onPressed: _pick,
                                    filled: true,
                                    iconSize: 26,
                                  ),
                          ],
                        ),
                      ),
                    ),
                    if (_library.docs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 50,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                            children: [
                              for (final f in _Filter.values)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _Chip(
                                    label: f.label,
                                    selected: f == _filter,
                                    onTap: () => setState(() => _filter = f),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_library.docs.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _Empty(),
                      )
                    else if (docs.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Nothing here yet.',
                            textAlign: TextAlign.center,
                            style: ui(15, weight: 600, color: c.muted),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          hasPlayer ? 130 : 32,
                        ),
                        sliver: SliverList.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _DocCard(
                            doc: docs[i],
                            h: h,
                            onTap: () => _openDoc(docs[i]),
                            onRemove: () => _confirmRemove(docs[i]),
                          ),
                        ),
                      ),
                  ],
                ),
                if (hasPlayer)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12 + MediaQuery.paddingOf(context).bottom,
                    child: _MiniPlayer(h: h, onOpen: _openPlayer),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.text : c.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: ui(
                14,
                weight: selected ? 800 : 600,
                color: selected ? c.bg : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.h,
    required this.onTap,
    required this.onRemove,
  });
  final Doc doc;
  final ReaderHandler h;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final current = h.doc?.id == doc.id;
    final speed = h.settings.speed;
    final pct = (doc.progress * 100).round();
    final top = [
      doc.kindLabel.toUpperCase(),
      if (doc.started) '$pct%',
      if (doc.position == 0 && !doc.finished) 'NEW',
    ].join(' · ');
    final meta = doc.finished
        ? 'Finished · ${friendlyDuration(doc.length)}'
        : doc.started
        ? '${friendlyDuration(doc.timeLeft(speed))} left'
        : friendlyDuration(
            Duration(milliseconds: (doc.length.inMilliseconds / speed).round()),
          );
    return Material(
      color: current ? c.selected : c.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onRemove,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (doc.recorded)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.mic_none_rounded,
                              size: 14,
                              color: c.muted,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            top,
                            style: ui(
                              12,
                              weight: 800,
                              spacing: 0.8,
                              color: c.muted,
                            ),
                          ),
                        ),
                        if (current)
                          ValueListenableBuilder<bool>(
                            valueListenable: h.playing,
                            builder: (_, playing, _) => Text(
                              playing ? 'Playing' : 'Paused',
                              style: ui(12, weight: 800, color: c.accentStrong),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      doc.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ui(
                        18,
                        weight: 800,
                        color: doc.finished ? c.muted : c.text,
                        height: 1.25,
                      ),
                    ),
                    if (doc.started) ...[
                      const SizedBox(height: 10),
                      ProgressTrack(
                        value: doc.progress,
                        height: 4,
                        thumb: false,
                      ),
                    ] else
                      const SizedBox(height: 6),
                    Text(meta, style: ui(13, weight: 600, color: c.muted)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert_rounded, color: c.muted),
                onSelected: (_) => onRemove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.h, required this.onOpen});
  final ReaderHandler h;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return Material(
      color: c.surface2,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: ValueListenableBuilder<int>(
          valueListenable: h.index,
          builder: (_, i, _) {
            final segs = h.segments;
            final sentence = segs.isEmpty
                ? ''
                : segs[i.clamp(0, segs.length - 1)].text;
            final progress = segs.isEmpty ? 0.0 : i / segs.length;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: c.track,
                  color: c.accentStrong,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.doc?.title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ui(14, weight: 800, color: c.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sentence,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ui(13, weight: 600, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(
                        icon: Icons.skip_next_rounded,
                        label: 'Next sentence',
                        onPressed: h.skipToNext,
                        plain: true,
                        iconSize: 26,
                      ),
                      const SizedBox(width: 4),
                      PlayPauseButton(h: h, size: 52),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
            child: Icon(Icons.headphones_rounded, size: 40, color: c.accent),
          ),
          const SizedBox(height: 20),
          Text(
            'Nothing to listen to yet',
            style: ui(20, weight: 800, color: c.text),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap + to add a PDF, Word, text or Markdown file, or an .earshot storyteller recording.\n\n'
            'From another app: Share → Earshot. For a Google Doc: Share & export → Send a copy → Word or PDF.',
            textAlign: TextAlign.center,
            style: ui(15, weight: 500, color: c.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
