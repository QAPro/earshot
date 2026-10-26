/// Voice & pace: speed, pauses, keep going, and the voice.
library;

import 'package:flutter/material.dart';

import '../audio/reader_handler.dart';
import '../services/library.dart';
import '../voices.dart';
import 'theme.dart';
import 'widgets.dart';

/// Set by the GitHub build (--dart-define=EARSHOT_BUILD=N); "dev" locally.
const earshotBuild = String.fromEnvironment(
  'EARSHOT_BUILD',
  defaultValue: 'dev',
);

/// The speeds the − / + buttons step through.
const _speeds = [
  0.75, 0.8, 0.9, 1.0, 1.1, 1.2, 1.25, 1.3, 1.4, 1.5, 1.6, 1.75, 2.0, //
];

Future<void> showVoiceSheet(BuildContext context, ReaderHandler h) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.95,
      builder: (context, scroll) => _VoiceSheet(h: h, scroll: scroll),
    ),
  );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({required this.h, required this.scroll});
  final ReaderHandler h;
  final ScrollController scroll;

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  ReaderHandler get h => widget.h;
  String? _previewing;
  bool _allVoices = false;

  Future<void> _step(int dir) async {
    final s = h.settings.speed;
    final next = dir > 0
        ? _speeds.firstWhere((v) => v > s + 0.001, orElse: () => _speeds.last)
        : _speeds.lastWhere((v) => v < s - 0.001, orElse: () => _speeds.first);
    await h.setSpeed(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final speed = h.settings.speed;
    final current = h.voice.value;
    final recorded = h.doc?.recorded ?? false;
    final shown = voices.where((v) => _allVoices || v.recommended).toList();

    Widget voiceRow(Voice v) {
      final selected = v.id == current.id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected ? c.selected : c.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: selected
                ? BorderSide(color: c.accent, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await h.setVoice(v);
              if (mounted) setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      selected: selected,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: v.name,
                              style: ui(
                                16,
                                weight: selected ? 800 : 700,
                                color: c.text,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ·  ${v.accent} ${v.female ? 'female' : 'male'}',
                              style: ui(13, weight: 600, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _previewing == v.id
                      ? const SizedBox(
                          width: 44,
                          height: 44,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : RoundButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Hear ${v.name}',
                          filled: selected,
                          onPressed: () async {
                            setState(() => _previewing = v.id);
                            await h.preview(v);
                            if (mounted) setState(() => _previewing = null);
                          },
                        ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        // Speed: one big number, big buttons
        Row(
          children: [
            RoundButton(
              icon: Icons.remove_rounded,
              label: 'Slower',
              onPressed: speed <= _speeds.first ? null : () => _step(-1),
              size: 64,
              iconSize: 30,
              onSurface: true,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    speedLabel(speed),
                    style: ui(52, weight: 800, color: c.text, spacing: -1.5),
                  ),
                  Text('speed', style: ui(13, weight: 600, color: c.muted)),
                ],
              ),
            ),
            RoundButton(
              icon: Icons.add_rounded,
              label: 'Faster',
              onPressed: speed >= _speeds.last ? null : () => _step(1),
              size: 64,
              iconSize: 30,
              onSurface: true,
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (recorded) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'This is a storyteller recording: its voices and pauses are built in. '
              'Speed works; the settings below apply to your other documents.',
              style: ui(14, weight: 600, color: c.muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
        ],

        const SectionLabel('Pauses'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final p in Pauses.values) ...[
              if (p != Pauses.values.first) const SizedBox(width: 8),
              Expanded(
                child: TileButton(
                  selected: h.settings.pauses == p,
                  onPressed: () async {
                    await h.setPauses(p);
                    if (mounted) setState(() {});
                  },
                  child: Text(p.label),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        Material(
          color: c.surface2,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            value: h.settings.continueToNext,
            onChanged: (on) async {
              await h.setContinueToNext(on);
              if (mounted) setState(() {});
            },
            title: Text(
              'Keep going',
              style: ui(15, weight: 800, color: c.text),
            ),
            subtitle: Text(
              'Start the next document when one ends',
              style: ui(13, weight: 600, color: c.muted),
            ),
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Voice'),
        const SizedBox(height: 8),
        ...shown.map(voiceRow),
        TextButton(
          onPressed: () => setState(() => _allVoices = !_allVoices),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size(0, 44),
          ),
          child: Text(
            _allVoices ? 'Just the voices you picked' : 'All 27 voices ›',
            style: ui(15, weight: 800, color: c.accentStrong),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Earshot build $earshotBuild',
            style: ui(12, weight: 600, color: c.muted),
          ),
        ),
      ],
    );
  }
}
