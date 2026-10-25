import 'package:flutter/material.dart';

import '../audio/reader_handler.dart';
import '../services/library.dart';
import '../voices.dart';

Future<void> showVoiceSheet(BuildContext context, ReaderHandler h) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
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
  late double _speed = widget.h.settings.speed;
  String? _previewing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final current = widget.h.voice.value;
    final recommended = voices.where((v) => v.recommended);
    final more = voices.where((v) => !v.recommended);

    Widget tile(Voice v) => ListTile(
      leading: Icon(
        v.id == current.id
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(v.label),
      trailing: IconButton(
        tooltip: 'Hear ${v.name}',
        icon: _previewing == v.id
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle_outline),
        onPressed: () async {
          setState(() => _previewing = v.id);
          await widget.h.preview(v);
          if (mounted) setState(() => _previewing = null);
        },
      ),
      onTap: () async {
        await widget.h.setVoice(v);
        if (mounted) setState(() {});
      },
    );

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(
            children: [
              Text('Speed', style: t.titleMedium),
              const Spacer(),
              Text('${_speed.toStringAsFixed(2)}×', style: t.titleMedium),
            ],
          ),
        ),
        Slider(
          value: _speed,
          min: 0.75,
          max: 2.0,
          divisions: 25,
          label: '${_speed.toStringAsFixed(2)}×',
          onChanged: (s) => setState(() => _speed = s),
          onChangeEnd: widget.h.setSpeed,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text('Pauses at punctuation', style: t.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<Pauses>(
            segments: [
              for (final p in Pauses.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {widget.h.settings.pauses},
            onSelectionChanged: (sel) async {
              await widget.h.setPauses(sel.first);
              if (mounted) setState(() {});
            },
          ),
        ),
        SwitchListTile(
          title: const Text('Continue to the next document'),
          subtitle: const Text(
            'When one ends, start the one below it in your list.',
          ),
          value: widget.h.settings.continueToNext,
          onChanged: (on) async {
            await widget.h.setContinueToNext(on);
            if (mounted) setState(() {});
          },
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text('Voices you picked', style: t.titleMedium),
        ),
        ...recommended.map(tile),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('More voices', style: t.titleMedium),
        ),
        ...more.map(tile),
      ],
    );
  }
}
