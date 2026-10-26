import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio/reader_handler.dart';
import 'services/library.dart';
import 'services/model_manager.dart';
import 'services/tts_worker.dart';

/// Everything the screens share.
class AppState {
  final library = Library();
  final settings = Settings();
  ReaderHandler? _handler;
  ReaderHandler get handler => _handler!;

  /// For rendering screens in tests without a voice model or audio.
  @visibleForTesting
  set handlerForTest(ReaderHandler h) => _handler = h;

  /// Files shared to the app from other apps (Android).
  static const _share = MethodChannel('earshot/share');

  Future<void> loadBasics() async {
    await settings.load();
    await library.load();
  }

  Future<bool> modelInstalled() => ModelManager.isInstalled();

  Future<void> startEngine({
    required Future<ReaderHandler> Function(ReaderHandler Function() builder)
    wrap,
  }) async {
    if (_handler != null) return;
    final tts = TtsWorker(await ModelManager.modelDir());
    _handler = await wrap(() => ReaderHandler(tts, library, settings));
    // Warm the model so the first sentence comes quickly.
    tts.start();
  }

  /// What went wrong if the previous run crashed (Android only, shown once).
  Future<String?> lastCrash() async {
    try {
      return await _share.invokeMethod<String>('getLastCrash');
    } on MissingPluginException {
      return null;
    }
  }

  /// Calls [onFile] with the path of any file shared into the app, now or later.
  Future<void> listenForShares(void Function(String path) onFile) async {
    _share.setMethodCallHandler((call) async {
      if (call.method == 'fileShared') onFile(call.arguments as String);
    });
    try {
      final initial = await _share.invokeMethod<String>('getInitialFile');
      if (initial != null) onFile(initial);
    } on MissingPluginException {
      // Not Android.
    }
  }
}
