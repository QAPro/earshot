/// Runs the Kokoro model on a background isolate so the UI never stalls.
/// Requests are handled one at a time.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../voices.dart';

class TtsWorker {
  TtsWorker(this.modelDir);

  final String modelDir;
  SendPort? _send;
  final _pending = <int, Completer<String>>{};
  var _nextId = 0;
  Future<void>? _starting;

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final rp = ReceivePort();
    final ready = Completer<SendPort>();
    rp.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List) {
        final c = _pending.remove(msg[0] as int);
        final result = msg[1] as String;
        if (result.startsWith('ERR:')) {
          c?.completeError(Exception(result.substring(4)));
        } else {
          c?.complete(result);
        }
      }
    });
    final threads = Platform.numberOfProcessors.clamp(2, 4);
    await Isolate.spawn(_main, [rp.sendPort, modelDir, threads]);
    _send = await ready.future;
  }

  /// Speaks [text] with [voice] into a WAV file at [outPath].
  Future<String> synth(
    String text,
    Voice voice,
    String outPath, {
    double silenceScale = 0.6,
  }) async {
    await start();
    final id = _nextId++;
    final c = Completer<String>();
    _pending[id] = c;
    _send!.send([id, text, voice.sid, voice.british, outPath, silenceScale]);
    return c.future;
  }
}

void _main(List<dynamic> args) {
  final reply = args[0] as SendPort;
  final dir = args[1] as String;
  final threads = args[2] as int;
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);

  sherpa.initBindings();
  sherpa.OfflineTts? tts;
  bool? loadedBritish;

  inbox.listen((msg) {
    final m = msg as List;
    final id = m[0] as int;
    try {
      final text = m[1] as String;
      final sid = m[2] as int;
      final british = m[3] as bool;
      final out = m[4] as String;
      final silenceScale = m[5] as double;
      if (tts == null || loadedBritish != british) {
        tts?.free();
        tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              kokoro: sherpa.OfflineTtsKokoroModelConfig(
                model: '$dir/model.onnx',
                voices: '$dir/voices.bin',
                tokens: '$dir/tokens.txt',
                dataDir: '$dir/espeak-ng-data',
                lexicon: british
                    ? '$dir/lexicon-gb-en.txt'
                    : '$dir/lexicon-us-en.txt',
                // eSpeak calls British English plain "en".
                lang: british ? 'en' : 'en-us',
              ),
              numThreads: threads,
              debug: false,
            ),
          ),
        );
        loadedBritish = british;
      }
      final audio = tts!.generateWithConfig(
        text: text,
        config: sherpa.OfflineTtsGenerationConfig(
          sid: sid,
          speed: 1.0,
          silenceScale: silenceScale,
        ),
      );
      if (audio.samples.isEmpty) throw Exception('No audio generated');
      final ok = sherpa.writeWave(
        filename: out,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!ok) throw Exception('Could not write audio file');
      reply.send([id, out]);
    } catch (e) {
      reply.send([id, 'ERR:$e']);
    }
  });
}
