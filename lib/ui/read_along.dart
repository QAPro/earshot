/// The whole document as text, with the sentence being read highlighted
/// (design A's reading view, grafted onto B). Full screen on a phone,
/// beside the player on a wide screen.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../audio/reader_handler.dart';
import '../services/segmenter.dart';
import 'theme.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

class ReadAlongView extends StatefulWidget {
  const ReadAlongView({super.key, required this.h, this.padding});
  final ReaderHandler h;
  final EdgeInsets? padding;

  @override
  State<ReadAlongView> createState() => _ReadAlongViewState();
}

class _ReadAlongViewState extends State<ReadAlongView> {
  ReaderHandler get h => widget.h;
  late List<_Para> _paras;
  late List<GlobalKey> _keys;
  final _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _load();
    h.docVersion.addListener(_onDocChanged);
    h.index.addListener(_onIndex);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(animate: false),
    );
  }

  @override
  void dispose() {
    h.docVersion.removeListener(_onDocChanged);
    h.index.removeListener(_onIndex);
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    _paras = _group(h.segments);
    _keys = List.generate(_paras.length, (_) => GlobalKey());
  }

  void _onDocChanged() {
    if (!mounted) return;
    setState(() {
      _load();
      _follow = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrent(animate: false),
    );
  }

  static List<_Para> _group(List<Segment> segs) {
    final out = <_Para>[];
    for (var i = 0; i < segs.length; i++) {
      if (out.isEmpty || out.last.paragraph != segs[i].paragraph) {
        out.add(_Para(segs[i].paragraph, i, label: segs[i].label));
      }
      out.last.texts.add(segs[i].text);
    }
    return out;
  }

  int _paraIndexOf(int segment) {
    var lo = 0, hi = _paras.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_paras[mid].first <= segment) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _onIndex() {
    if (_follow) _scrollToCurrent();
  }

  void _scrollToCurrent({bool animate = true}) {
    if (_paras.isEmpty) return;
    final ctx = _keys[_paraIndexOf(h.index.value)].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (n) {
            if (n.direction != ScrollDirection.idle && _follow) {
              setState(() => _follow = false);
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scroll,
            padding:
                widget.padding ?? const EdgeInsets.fromLTRB(24, 16, 24, 120),
            child: Center(
              child: ConstrainedBox(
                // A comfortable line length, even on a wide monitor.
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _paras.length; i++)
                      Padding(
                        key: _keys[i],
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _ParagraphText(
                          para: _paras[i],
                          index: h.index,
                          onTap: (seg) async {
                            setState(() => _follow = true);
                            await h.jumpTo(seg);
                            if (!h.playing.value) await h.play();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!_follow)
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              color: c.text,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  setState(() => _follow = true);
                  _scrollToCurrent();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location_rounded, size: 18, color: c.bg),
                      const SizedBox(width: 8),
                      Text(
                        'Back to reading',
                        style: ui(14, weight: 700, color: c.bg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Para {
  _Para(this.paragraph, this.first, {this.label});
  final int paragraph;
  final int first;
  final String? label;
  final texts = <String>[];
}

/// One paragraph; rebuilds only when the highlight enters, moves within or
/// leaves it.
class _ParagraphText extends StatefulWidget {
  const _ParagraphText({
    required this.para,
    required this.index,
    required this.onTap,
  });
  final _Para para;
  final ValueNotifier<int> index;
  final void Function(int segment) onTap;

  @override
  State<_ParagraphText> createState() => _ParagraphTextState();
}

class _ParagraphTextState extends State<_ParagraphText> {
  late int _active = _activeFor(widget.index.value);
  final _recognizers = <TapGestureRecognizer>[];

  int _activeFor(int i) {
    final local = i - widget.para.first;
    return local >= 0 && local < widget.para.texts.length ? local : -1;
  }

  void _listen() {
    final a = _activeFor(widget.index.value);
    if (a != _active) setState(() => _active = a);
  }

  @override
  void initState() {
    super.initState();
    widget.index.addListener(_listen);
    for (var k = 0; k < widget.para.texts.length; k++) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onTap(widget.para.first + k),
      );
    }
  }

  @override
  void dispose() {
    widget.index.removeListener(_listen);
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final base = reading(19, color: c.text);
    final hl = base.copyWith(backgroundColor: c.highlight);
    final isPause =
        widget.para.texts.length == 1 && widget.para.texts.first.isEmpty;
    if (isPause) {
      return Text('· · ·', style: ui(16, weight: 700, color: c.dim));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.para.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              widget.para.label!.toUpperCase(),
              style: ui(12, weight: 800, spacing: 1.1, color: c.accentStrong),
            ),
          ),
        Text.rich(
          TextSpan(
            children: [
              for (var k = 0; k < widget.para.texts.length; k++)
                TextSpan(
                  text: '${widget.para.texts[k]} ',
                  style: k == _active ? hl : base,
                  recognizer: _recognizers[k],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-along as its own screen (phones): the text, plus a slim control
/// bar so you can stay here while listening.
class ReadAlongScreen extends StatelessWidget {
  const ReadAlongScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final h = state.handler;
    final c = EarshotColors.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  RoundButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    label: 'Back to the player',
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: h.docVersion,
                      builder: (_, _, _) => Text(
                        h.doc?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ui(16, weight: 800, color: c.text),
                      ),
                    ),
                  ),
                  RoundButton(
                    icon: Icons.tune_rounded,
                    label: 'Voice and pace',
                    onPressed: () => showVoiceSheet(context, h),
                  ),
                ],
              ),
            ),
            Expanded(child: ReadAlongView(h: h)),
            Container(
              color: c.surface,
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RoundButton(
                    icon: Icons.skip_previous_rounded,
                    label: 'Previous sentence',
                    onPressed: h.skipToPrevious,
                    size: 56,
                    iconSize: 28,
                    onSurface: true,
                  ),
                  PlayPauseButton(h: h, size: 68),
                  RoundButton(
                    icon: Icons.skip_next_rounded,
                    label: 'Next sentence',
                    onPressed: h.skipToNext,
                    size: 56,
                    iconSize: 28,
                    onSurface: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
