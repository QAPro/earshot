/// "Now playing": the sentence being read, large enough to read at arm's
/// length, with the sentences either side faded, and big controls.
/// On a wide screen (Windows) the whole text sits beside it.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../audio/reader_handler.dart';
import '../voices.dart';
import 'read_along.dart';
import 'theme.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.state});
  final AppState state;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  ReaderHandler get h => widget.state.handler;
  late DocTimeline _timeline = DocTimeline(h.segments);

  @override
  void initState() {
    super.initState();
    h.docVersion.addListener(_onDoc);
  }

  @override
  void dispose() {
    h.docVersion.removeListener(_onDoc);
    super.dispose();
  }

  void _onDoc() {
    if (mounted) setState(() => _timeline = DocTimeline(h.segments));
  }

  Future<void> _switchDoc(bool next) async {
    final moved = next ? await h.nextDocument() : await h.previousDocument();
    if (!moved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'This is the last document in your list.'
                : 'This is the first document in your list.',
          ),
        ),
      );
    }
  }

  Future<void> _openSheet() async {
    await showVoiceSheet(context, h);
    if (mounted) setState(() {}); // speed/voice labels
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final player = _Player(
      h: h,
      timeline: _timeline,
      wide: wide,
      onReadAlong: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReadAlongScreen(state: widget.state)),
      ),
      onSheet: _openSheet,
      onSwitchDoc: _switchDoc,
    );
    if (!wide) return Scaffold(body: SafeArea(child: player));
    final c = EarshotColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(width: 440, child: player),
            VerticalDivider(width: 1, color: c.track),
            Expanded(
              child: ReadAlongView(
                h: h,
                padding: const EdgeInsets.fromLTRB(40, 48, 40, 120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({
    required this.h,
    required this.timeline,
    required this.wide,
    required this.onReadAlong,
    required this.onSheet,
    required this.onSwitchDoc,
  });

  final ReaderHandler h;
  final DocTimeline timeline;
  final bool wide;
  final VoidCallback onReadAlong;
  final VoidCallback onSheet;
  final void Function(bool next) onSwitchDoc;

  /// Who is speaking at [i] in a cast document (the label sits on the first
  /// sentence of each line).
  String? _speaker(int i) {
    final segs = h.segments;
    for (var k = i; k >= 0; k--) {
      if (segs[k].paragraph != segs[i].paragraph) break;
      if (segs[k].label != null) return segs[k].label;
    }
    return null;
  }

  /// Long sentences get smaller so they still fit without scrolling.
  static double _sizeFor(String s) => s.length <= 90
      ? 30
      : s.length <= 170
      ? 26
      : s.length <= 250
      ? 23
      : 20;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final doc = h.doc;
    final speed = h.settings.speed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              RoundButton(
                icon: Icons.keyboard_arrow_down_rounded,
                label: 'Back to library',
                onPressed: () => Navigator.of(context).pop(),
                iconSize: 26,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'NOW PLAYING',
                      style: ui(11, weight: 800, spacing: 1.6, color: c.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doc?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui(15, weight: 800, color: c.text),
                    ),
                  ],
                ),
              ),
              if (wide)
                const SizedBox(width: 44)
              else
                RoundButton(
                  icon: Icons.menu_book_rounded,
                  label: 'Read along',
                  onPressed: onReadAlong,
                  iconSize: 20,
                ),
            ],
          ),

          // The sentence being read, with its neighbours faded
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: h.index,
              builder: (context, i, _) {
                final segs = h.segments;
                if (segs.isEmpty) return const SizedBox();
                final idx = i.clamp(0, segs.length - 1);
                final current = segs[idx].text.isEmpty
                    ? '· · ·'
                    : segs[idx].text;
                final prev = idx > 0 ? segs[idx - 1].text : '';
                final next = idx + 1 < segs.length ? segs[idx + 1].text : '';
                final speaker = _speaker(idx);
                return Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prev,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: ui(
                            18,
                            weight: 500,
                            color: c.dim,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey('${h.doc?.id}-$idx'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (speaker != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    speaker.toUpperCase(),
                                    style: ui(
                                      13,
                                      weight: 800,
                                      spacing: 1.2,
                                      color: c.accentStrong,
                                    ),
                                  ),
                                ),
                              Text(
                                current,
                                style: ui(
                                  _sizeFor(current),
                                  weight: 800,
                                  color: c.text,
                                  height: 1.28,
                                  spacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          next,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: ui(
                            18,
                            weight: 500,
                            color: c.dim,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Progress, with a mark at each paragraph; tap or drag to jump
          ValueListenableBuilder<int>(
            valueListenable: h.index,
            builder: (context, i, _) {
              final para = h.segments.isEmpty
                  ? 0
                  : h.segments[i.clamp(0, h.segments.length - 1)].paragraph;
              return Column(
                children: [
                  ProgressTrack(
                    value: timeline.fractionAt(i),
                    marks: timeline.paragraphMarks(),
                    onSeek: (f) => h.jumpTo(timeline.indexAt(f)),
                  ),
                  Row(
                    children: [
                      RoundButton(
                        icon: Icons.first_page_rounded,
                        label: 'Start of document',
                        onPressed: h.toStart,
                        plain: true,
                        size: 44,
                      ),
                      Text(
                        clock(timeline.elapsed(i, speed)),
                        style: ui(13, weight: 700, color: c.muted),
                      ),
                      Expanded(
                        child: Text(
                          'Paragraph ${para + 1} of ${timeline.paragraphCount}',
                          textAlign: TextAlign.center,
                          style: ui(13, weight: 700, color: c.muted),
                        ),
                      ),
                      Text(
                        '−${clock(timeline.remaining(i, speed))}',
                        style: ui(13, weight: 700, color: c.muted),
                      ),
                      RoundButton(
                        icon: Icons.last_page_rounded,
                        label: 'End of document',
                        onPressed: h.toEnd,
                        plain: true,
                        size: 44,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Transport
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RoundButton(
                icon: Icons.fast_rewind_rounded,
                label: 'Previous paragraph',
                onPressed: h.previousParagraph,
                plain: true,
                size: 56,
                iconSize: 30,
              ),
              RoundButton(
                icon: Icons.skip_previous_rounded,
                label: 'Previous sentence',
                onPressed: h.skipToPrevious,
                size: 60,
                iconSize: 30,
              ),
              PlayPauseButton(h: h),
              RoundButton(
                icon: Icons.skip_next_rounded,
                label: 'Next sentence',
                onPressed: h.skipToNext,
                size: 60,
                iconSize: 30,
              ),
              RoundButton(
                icon: Icons.fast_forward_rounded,
                label: 'Next paragraph',
                onPressed: h.nextParagraph,
                plain: true,
                size: 56,
                iconSize: 30,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Documents, speed, voice
          Row(
            children: [
              Expanded(
                child: TileButton(
                  semanticLabel: 'Previous document',
                  onPressed: () => onSwitchDoc(false),
                  child: const Text('‹ Prev doc'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TileButton(
                  semanticLabel: 'Speed, ${speedLabel(speed)}. Change',
                  onPressed: onSheet,
                  child: Text(
                    speedLabel(speed),
                    style: ui(15, weight: 800, color: c.text),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TileButton(
                  semanticLabel: 'Voice. Change',
                  onPressed: onSheet,
                  child: ValueListenableBuilder<Voice>(
                    valueListenable: h.voice,
                    builder: (_, v, _) => Text(
                      doc?.recorded ?? false ? 'Story' : v.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TileButton(
                  semanticLabel: 'Next document',
                  onPressed: () => onSwitchDoc(true),
                  child: const Text('Next doc ›'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
