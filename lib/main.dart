import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/home_screen.dart';
import 'ui/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.loadBasics();
  runApp(EarshotApp(state: state));
}

class EarshotApp extends StatelessWidget {
  const EarshotApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E6F6A);
    return MaterialApp(
      title: 'Earshot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: _Root(state: state),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root({required this.state});
  final AppState state;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _installed;

  @override
  void initState() {
    super.initState();
    widget.state.modelInstalled().then((ok) async {
      if (ok) await _startEngine();
      if (mounted) setState(() => _installed = ok);
    });
  }

  Future<void> _startEngine() async {
    await widget.state.startEngine(
      wrap: (builder) async => Platform.isAndroid
          ? await AudioService.init(
              builder: builder,
              config: const AudioServiceConfig(
                androidNotificationChannelId:
                    'tech.baileyenterprises.earshot.playback',
                androidNotificationChannelName: 'Reading aloud',
                androidNotificationIcon: 'drawable/ic_stat_earshot',
                androidNotificationOngoing: false,
                androidStopForegroundOnPause: true,
              ),
            )
          : builder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed;
    if (installed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!installed) {
      return SetupScreen(
        onDone: () async {
          await _startEngine();
          if (mounted) setState(() => _installed = true);
        },
      );
    }
    return HomeScreen(state: widget.state);
  }
}
