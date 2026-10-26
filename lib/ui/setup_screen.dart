import 'package:flutter/material.dart';

import '../services/model_manager.dart';
import 'theme.dart';
import 'widgets.dart';

/// First launch: download the voices once.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  ModelProgress? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _error = null;
      _progress = const ModelProgress('Starting', 0);
    });
    try {
      await for (final p in ModelManager.install()) {
        if (mounted) setState(() => _progress = p);
      }
      await widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EarshotColors.of(context);
    final p = _progress;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.headphones_rounded,
                        size: 44,
                        color: c.onAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Earshot',
                    textAlign: TextAlign.center,
                    style: ui(36, weight: 800, spacing: -1, color: c.text),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reads your documents aloud, entirely on this device.\n\n'
                    'First it needs its voices: a one-time download of about $modelSizeMb MB. '
                    'Use Wi-Fi if you can. After that it works offline.',
                    textAlign: TextAlign.center,
                    style: ui(16, weight: 500, color: c.muted, height: 1.5),
                  ),
                  const SizedBox(height: 36),
                  if (p == null)
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _install,
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.onAccent,
                          textStyle: ui(17, weight: 800),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download voices'),
                      ),
                    )
                  else ...[
                    ProgressTrack(
                      value: p.fraction ?? 0,
                      thumb: false,
                      height: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.fraction == null || p.stage != 'Downloading voices'
                          ? '${p.stage}…'
                          : '${p.stage}: ${(p.fraction! * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: ui(14, weight: 700, color: c.muted),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: ui(
                        14,
                        weight: 600,
                        color: const Color(0xFFE5484D),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
