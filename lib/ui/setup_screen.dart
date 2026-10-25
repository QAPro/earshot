import 'package:flutter/material.dart';

import '../services/model_manager.dart';

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
    final t = Theme.of(context).textTheme;
    final p = _progress;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.hearing,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Earshot',
                style: t.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'Earshot reads your documents aloud, entirely on this device.\n\n'
                'First it needs its voices: a one-time download of about $modelSizeMb MB. '
                'Use Wi-Fi if you can. After that it works offline.',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (p == null)
                FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.download),
                  label: const Text('Download voices'),
                )
              else ...[
                LinearProgressIndicator(value: p.fraction),
                const SizedBox(height: 12),
                Text(
                  p.fraction == null || p.stage != 'Downloading voices'
                      ? '${p.stage}…'
                      : '${p.stage}: ${(p.fraction! * 100).round()}%',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
