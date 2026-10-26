/// Shared pieces of the "Now Playing" design.
library;

import 'package:flutter/material.dart';

import '../audio/reader_handler.dart';
import '../services/segmenter.dart';
import 'theme.dart';

/// "45 s", "9 min", "1 h 14 min".
String friendlyDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

/// "1×", "1.25×", "1.5×".
String speedLabel(double s) {
  var t = s.toStringAsFixed(2);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$t×';
}

/// "3:41", "1:02:05".
String clock(Duration d) {
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '${d.inHours}:$m:$s';
  }
  return '${d.inMinutes}:$s';
}

/// Where each sentence sits along the document, by time: exact for
/// recordings, estimated from text length otherwise.
class DocTimeline {
  DocTimeline(this.segments) {
    var acc = 0.0;
    for (final s in segments) {
      _starts.add(acc);
      acc += s.startMs != null
          ? ((s.endMs ?? s.startMs!) - s.startMs!).toDouble()
          : (s.text.length / 13 * 1000) + s.pauseMs;
    }
    _total = acc <= 0 ? 1 : acc;
    if (segments.isNotEmpty && segments.first.startMs != null) {
      // Recordings: use the real positions, gaps included.
      _starts
        ..clear()
        ..addAll(segments.map((s) => s.startMs!.toDouble()));
      _total = (segments.last.endMs ?? segments.last.startMs!).toDouble();
    }
  }

  final List<Segment> segments;
  final _starts = <double>[];
  late double _total;

  double fractionAt(int index) => segments.isEmpty
      ? 0
      : _starts[index.clamp(0, segments.length - 1)] / _total;

  int indexAt(double fraction) {
    final target = fraction.clamp(0, 1) * _total;
    var i = 0;
    while (i + 1 < _starts.length && _starts[i + 1] <= target) {
      i++;
    }
    return i;
  }

  Duration elapsed(int index, double speed) =>
      Duration(milliseconds: (fractionAt(index) * _total / speed).round());

  Duration remaining(int index, double speed) => Duration(
    milliseconds: ((1 - fractionAt(index)) * _total / speed).round(),
  );

  /// Fractions where paragraphs start (skips the first). Empty when there
  /// are too many to draw as separate marks.
  List<double> paragraphMarks() {
    final out = <double>[];
    for (var i = 1; i < segments.length; i++) {
      if (segments[i].paragraph != segments[i - 1].paragraph) {
        out.add(fractionAt(i));
      }
    }
    return out.length > 60 ? const [] : out;
  }

  int get paragraphCount => segments.isEmpty ? 0 : segments.last.paragraph + 1;
}

/// A round button with an icon. [filled] = the amber play-button style.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.filled = false,
    this.plain = false,
    this.onSurface = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool filled;

  /// No background at all (secondary controls).
  final bool plain;

  /// Sits on a card, sheet or bar (not the page): uses the stronger fill
  /// so the circle stays visible.
  final bool onSurface;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final bg = filled
        ? c.accent
        : plain
        ? Colors.transparent
        : onSurface
        ? c.surface2
        : c.surface;
    final fg = filled ? c.onAccent : (plain ? c.muted : c.text);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The big amber play/pause button; a ring spins while the first audio is
/// being prepared.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.h, this.size = 92});
  final ReaderHandler h;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: h.playing,
      builder: (_, playing, _) => ValueListenableBuilder<bool>(
        valueListenable: h.waiting,
        builder: (_, waiting, _) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RoundButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: playing ? 'Pause' : 'Play',
                onPressed: playing ? h.pause : h.play,
                size: size,
                iconSize: size * 0.42,
                filled: true,
              ),
              if (playing && waiting)
                IgnorePointer(
                  child: SizedBox(
                    width: size - 6,
                    height: size - 6,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: c.onAccent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A progress bar with paragraph marks; tap or drag to jump there.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    super.key,
    required this.value,
    this.marks = const [],
    this.onSeek,
    this.height = 6,
    this.thumb = true,
  });

  final double value;
  final List<double> marks;
  final ValueChanged<double>? onSeek;
  final double height;
  final bool thumb;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void seek(Offset local) => onSeek?.call((local.dx / w).clamp(0, 1));
        return Semantics(
          slider: true,
          value: '${(value * 100).round()}%',
          label: 'Position in document',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onSeek == null ? null : (d) => seek(d.localPosition),
            onHorizontalDragUpdate: onSeek == null
                ? null
                : (d) => seek(d.localPosition),
            child: SizedBox(
              height: 28,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: c.track,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                  Container(
                    width: w * value.clamp(0, 1),
                    height: height,
                    decoration: BoxDecoration(
                      color: c.accentStrong,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                  for (final m in marks)
                    Positioned(
                      left: w * m - 1,
                      child: Container(
                        width: 2,
                        height: height + 6,
                        color: c.bg,
                      ),
                    ),
                  if (thumb)
                    Positioned(
                      left: w * value.clamp(0, 1) - 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: c.text,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A rounded rectangle button for the player's bottom row and choices.
class TileButton extends StatelessWidget {
  const TileButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.height = 48,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? c.text : c.surface2,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: height,
            child: Center(
              child: DefaultTextStyle.merge(
                style: ui(
                  14,
                  weight: selected ? 800 : 700,
                  color: selected ? c.bg : c.text,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: selected ? c.bg : c.text),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small caps section label: "PAUSES", "VOICE".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: ui(
      12,
      weight: 700,
      spacing: 1.2,
      color: EarshotColors.of(context).muted,
    ),
  );
}
