/// Downloads the Kokoro voice model once, verifies it and unpacks it.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const modelUrl =
    'https://github.com/QAPro/earshot/releases/download/model-kokoro-en-v1.0/kokoro-en-v1_0.zip';
const modelSha256 =
    '8a8ddb3661db5a8b051a1af91ac3a11861a7d3b29255e6d93b97670fcc2c64b7';
const modelSizeMb = 349;
const _modelFolder = 'kokoro-en-v1_0';

class ModelProgress {
  const ModelProgress(this.stage, [this.fraction]);
  final String stage;
  final double? fraction;
}

class ModelManager {
  static Future<String> modelDir() async {
    final base = await getApplicationSupportDirectory();
    return p.join(base.path, 'models', _modelFolder);
  }

  static Future<bool> isInstalled() async =>
      File(p.join(await modelDir(), '.complete')).exists();

  static Stream<ModelProgress> install() async* {
    final dir = await modelDir();
    final parent = p.dirname(dir);
    await Directory(parent).create(recursive: true);
    final zip = File(p.join(parent, 'download.zip'));

    yield const ModelProgress('Downloading voices', 0);
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(modelUrl)));
      if (res.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength ?? modelSizeMb * 1024 * 1024;
      final sink = zip.openWrite();
      final digestOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestOut);
      var received = 0;
      var lastReport = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (received - lastReport > 2 * 1024 * 1024) {
          lastReport = received;
          yield ModelProgress('Downloading voices', received / total);
        }
      }
      await sink.close();
      hasher.close();
      if (digestOut.value.toString() != modelSha256) {
        await zip.delete();
        throw const FileSystemException(
          'The download was corrupted. Please try again.',
        );
      }
    } finally {
      client.close();
    }

    yield const ModelProgress('Unpacking');
    final dirExists = Directory(dir);
    if (await dirExists.exists()) await dirExists.delete(recursive: true);
    final zipPath = zip.path;
    await Isolate.run(() => extractFileToDisk(zipPath, parent));
    await zip.delete();
    await File(p.join(dir, '.complete')).writeAsString('ok');
    yield const ModelProgress('Done', 1);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
