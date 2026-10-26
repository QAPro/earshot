/// The list of imported documents, with each one's reading position.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extract.dart';
import 'segmenter.dart';

class Doc {
  Doc({
    required this.id,
    required this.title,
    required this.filePath,
    required this.textPath,
    required this.total,
    this.position = 0,
    this.audioPath,
    DateTime? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now();

  final String id;
  final String title;
  final String filePath;
  final String textPath;
  final int total;
  int position;

  /// Set for a storyteller recording (.earshot): the audio to play. Its
  /// textPath then holds the recording's script with sentence timings.
  final String? audioPath;
  bool get recorded => audioPath != null;
  DateTime lastOpened;

  double get progress => total == 0 ? 0 : (position / total).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'textPath': textPath,
    'total': total,
    'position': position,
    if (audioPath != null) 'audioPath': audioPath,
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory Doc.fromJson(Map<String, dynamic> j) => Doc(
    id: j['id'] as String,
    title: j['title'] as String,
    filePath: j['filePath'] as String,
    textPath: j['textPath'] as String,
    total: j['total'] as int,
    position: j['position'] as int? ?? 0,
    audioPath: j['audioPath'] as String?,
    lastOpened: DateTime.tryParse(j['lastOpened'] as String? ?? ''),
  );
}

class Library {
  static const _key = 'library.v1';
  final List<Doc> docs = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    docs.clear();
    if (raw != null) {
      for (final j in jsonDecode(raw) as List) {
        final d = Doc.fromJson(j as Map<String, dynamic>);
        if (File(d.textPath).existsSync()) docs.add(d);
      }
    }
    _sort();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(docs.map((d) => d.toJson()).toList()),
    );
  }

  /// Stable order: newest added first (ids are creation timestamps), so
  /// "next document" always means the one below in the list.
  void _sort() =>
      docs.sort((a, b) => int.parse(b.id).compareTo(int.parse(a.id)));

  /// The document below [d] in the list (+1) or above it (-1), if any.
  Doc? neighbour(Doc d, int step) {
    final i = docs.indexWhere((x) => x.id == d.id);
    final j = i + step;
    return i < 0 || j < 0 || j >= docs.length ? null : docs[j];
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'earshot-library'));
    await d.create(recursive: true);
    return d;
  }

  /// Copies the document into app storage, extracts its text and adds it.
  /// Throws [ExtractException] if the file can't be read.
  Future<Doc> import(String name, Stream<List<int>> bytes) async {
    final ext = p.extension(name).toLowerCase();
    if (!supportedExtensions.contains(ext.replaceFirst('.', ''))) {
      throw ExtractException(
        'Earshot can read PDF, Word (.docx), text and Markdown files. "$name" isn\'t one of those.',
      );
    }
    final dir = await _dir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    if (ext == '.earshot') return _importRecording(id, dir, name, bytes);
    final file = File(p.join(dir.path, '$id$ext'));
    final sink = file.openWrite();
    await sink.addStream(bytes);
    await sink.close();
    try {
      final text = await extractText(file.path);
      final textFile = File(p.join(dir.path, '$id.txt.cache'));
      await textFile.writeAsString(text);
      final doc = Doc(
        id: id,
        title: p.basenameWithoutExtension(name),
        filePath: file.path,
        textPath: textFile.path,
        total: segment(text).length,
      );
      docs.insert(0, doc);
      await save();
      return doc;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// A storyteller recording made by render/render.py: a zip holding
  /// audio.mp3 and script.json (sentences with their timings).
  Future<Doc> _importRecording(
    String id,
    Directory dir,
    String name,
    Stream<List<int>> bytes,
  ) async {
    final chunks = BytesBuilder(copy: false);
    await for (final c in bytes) {
      chunks.add(c);
    }
    final invalid = ExtractException(
      '"$name" isn\'t a valid Earshot recording.',
    );
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(chunks.takeBytes());
    } catch (_) {
      throw invalid;
    }
    final audio = zip.findFile('audio.mp3');
    final script = zip.findFile('script.json');
    if (audio == null || script == null) throw invalid;
    final json =
        jsonDecode(utf8.decode(script.content)) as Map<String, dynamic>;
    if (json['format'] != 'earshot-audio') throw invalid;
    final audioFile = File(p.join(dir.path, '$id.mp3'));
    await audioFile.writeAsBytes(audio.content);
    final scriptFile = File(p.join(dir.path, '$id.recording.json'));
    await scriptFile.writeAsBytes(script.content);
    final doc = Doc(
      id: id,
      title: (json['title'] as String?) ?? p.basenameWithoutExtension(name),
      filePath: audioFile.path,
      textPath: scriptFile.path,
      audioPath: audioFile.path,
      total: (json['segments'] as List).length,
    );
    docs.insert(0, doc);
    await save();
    return doc;
  }

  Future<List<Segment>> segmentsFor(Doc d) async {
    final raw = await File(d.textPath).readAsString();
    if (!d.recorded) return segment(raw);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return [
      for (final s in (json['segments'] as List).cast<Map<String, dynamic>>())
        Segment(
          s['paragraph'] as int,
          s['text'] as String,
          label: s['label'] as String?,
          startMs: s['start'] as int,
          endMs: s['end'] as int,
        ),
    ];
  }

  Future<void> remove(Doc d) async {
    docs.removeWhere((x) => x.id == d.id);
    for (final f in [d.filePath, d.textPath]) {
      final file = File(f);
      if (await file.exists()) await file.delete();
    }
    await save();
  }

  Future<void> touch(Doc d) async {
    d.lastOpened = DateTime.now();
    _sort();
    await save();
  }
}

/// How long to pause at punctuation and between paragraphs.
enum Pauses {
  short('Short', 0.2, 150, 40),
  natural('Natural', 0.6, 450, 120),
  long('Long', 1.0, 800, 250);

  const Pauses(
    this.label,
    this.silenceScale,
    this.paragraphMs,
    this.castLineMs,
  );
  final String label;

  /// Kokoro/sherpa-onnx silence scale: stretches pauses at commas, colons,
  /// sentence ends. 0.2 (the library default) races through punctuation.
  final double silenceScale;

  /// Extra pause after the last sentence of a paragraph or heading.
  final int paragraphMs;

  /// In a cast document every line is a paragraph, so lines follow each
  /// other much more closely; `[pause]` lines do the dramatic waiting.
  final int castLineMs;
}

class Settings {
  static const _voiceKey = 'voice';
  static const _speedKey = 'speed';
  static const _pausesKey = 'pauses';
  static const _continueKey = 'continueToNext';

  String voiceId = 'af_heart';
  double speed = 1.0;
  Pauses pauses = Pauses.natural;
  bool continueToNext = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    voiceId = prefs.getString(_voiceKey) ?? voiceId;
    speed = prefs.getDouble(_speedKey) ?? speed;
    pauses = Pauses.values.asNameMap()[prefs.getString(_pausesKey)] ?? pauses;
    continueToNext = prefs.getBool(_continueKey) ?? continueToNext;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceKey, voiceId);
    await prefs.setDouble(_speedKey, speed);
    await prefs.setString(_pausesKey, pauses.name);
    await prefs.setBool(_continueKey, continueToNext);
  }
}
