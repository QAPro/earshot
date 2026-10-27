/// Reads a document aloud sentence by sentence. Generates a few sentences
/// ahead of playback, and exposes lock-screen / headset controls on Android
/// through audio_service.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/library.dart';
import '../services/segmenter.dart';
import '../services/tts_worker.dart';
import '../voices.dart';

const _lookAhead = 3;

class ReaderHandler extends BaseAudioHandler {
  ReaderHandler(this.tts, this.library, this.settings) {
    _player.processingStateStream.listen((s) {
      if (s != ProcessingState.completed) return;
      if (_recorded) {
        _recordingFinished();
      } else {
        _finishSegment();
      }
    });
    _player.positionStream.listen(_onPosition);
    _initSession();
  }

  final TtsWorker tts;
  final Library library;
  final Settings settings;
  final _player = AudioPlayer();
  final _previewPlayer = AudioPlayer();

  /// UI state.
  final index = ValueNotifier<int>(0);
  final playing = ValueNotifier<bool>(false);
  final waiting = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);
  final voice = ValueNotifier<Voice>(voices.first);

  /// Bumps whenever a different document is opened, so screens can rebuild.
  final docVersion = ValueNotifier<int>(0);

  Doc? doc;
  List<Segment> segments = const [];

  /// A storyteller recording plays one audio file; the highlighted sentence
  /// follows the play position instead of generating speech.
  bool get _recorded => doc?.recorded ?? false;
  String? _loadedRecording;
  bool _seeking = false;

  int _run = 0; // bumps on every stop/jump so stale loops exit
  Completer<void>? _segmentDone;
  String? _cacheDir;

  // Generated audio: key -> file path ('' = nothing to say).
  final _done = <String, String>{};
  final _waiters = <String, List<Completer<String>>>{};
  String? _inflight;

  Future<void> _initSession() async {
    voice.value = voiceById(settings.voiceId);
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      session.becomingNoisyEventStream.listen((_) => pause()); // headphones out
      session.interruptionEventStream.listen((e) {
        if (e.begin) pause();
      });
    } catch (_) {
      // Not available on every platform (e.g. Windows); playback still works.
    }
  }

  Future<String> _cache() async {
    if (_cacheDir != null) return _cacheDir!;
    final d = Directory(
      p.join((await getTemporaryDirectory()).path, 'earshot-audio'),
    );
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
    return _cacheDir = d.path;
  }

  // ---------------------------------------------------------------- loading

  Future<void> open(Doc d, List<Segment> segs) async {
    await _stopPlayback();
    _loadedRecording = null;
    doc = d;
    segments = segs;
    _clearAudio();
    // A finished document starts again from the top.
    index.value = d.position >= segs.length ? 0 : d.position;
    error.value = null;
    await library.touch(d);
    docVersion.value++;
    _publishItem();
    _publishState();
  }

  // --------------------------------------------------------------- controls

  @override
  Future<void> play() async {
    if (doc == null || segments.isEmpty) return;
    if (index.value >= segments.length) index.value = 0;
    playing.value = true;
    _publishState();
    if (_recorded) {
      await _playRecording();
      return;
    }
    unawaited(_loop(++_run));
  }

  @override
  Future<void> pause() async {
    if (!playing.value) return;
    playing.value = false;
    if (_recorded) {
      await _player.pause(); // resumes exactly where it stopped
    } else {
      await _stopPlayback();
    }
    _publishState();
  }

  @override
  Future<void> stop() async {
    await pause();
    await super.stop();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.next:
        return skipToNext();
      case MediaButton.previous:
        return skipToPrevious();
      case MediaButton.media:
        return playing.value ? pause() : play();
    }
  }

  @override
  Future<void> skipToNext() => jumpTo(index.value + 1);

  @override
  Future<void> skipToPrevious() => jumpTo(index.value - 1);

  @override
  Future<void> fastForward() => nextParagraph();

  @override
  Future<void> rewind() => previousParagraph();

  Future<void> nextParagraph() async {
    final cur = _paragraphOf(index.value);
    final i = segments.indexWhere((s) => s.paragraph > cur, index.value);
    await jumpTo(i < 0 ? segments.length - 1 : i);
  }

  /// Back to the start of this paragraph, or the previous one if already
  /// at its start.
  Future<void> previousParagraph() async {
    var i = index.value;
    final cur = _paragraphOf(i);
    final startOfCur = segments.indexWhere((s) => s.paragraph == cur);
    var target = startOfCur;
    if (i == startOfCur && cur > 0) {
      target = segments.indexWhere((s) => s.paragraph == cur - 1);
    }
    await jumpTo(max(0, target));
  }

  int _paragraphOf(int i) => segments.isEmpty
      ? 0
      : segments[i.clamp(0, segments.length - 1)].paragraph;

  Future<void> jumpTo(int i) async {
    if (segments.isEmpty) return;
    if (_recorded) {
      index.value = i.clamp(0, segments.length - 1);
      _savePosition();
      _publishItem();
      await _seekToCurrent();
      return;
    }
    final wasPlaying = playing.value;
    await _stopPlayback();
    index.value = i.clamp(0, segments.length - 1);
    _savePosition();
    _publishItem();
    if (wasPlaying) {
      unawaited(_loop(++_run));
    } else {
      _publishState();
    }
  }

  // ------------------------------------------------- storyteller recordings

  Future<void> _ensureRecordingLoaded() async {
    final path = doc!.audioPath!;
    if (_loadedRecording == path) return;
    await _player.setAudioSource(
      ProgressiveAudioSource(
        Uri.file(path),
        // Exact seeking in MP3s on Android, even variable-bitrate ones made
        // by older renderers (seek-table estimates put the highlight out of
        // step with the audio after a jump).
        options: const ProgressiveAudioSourceOptions(
          androidExtractorOptions: AndroidExtractorOptions(
            mp3Flags: AndroidExtractorOptions.flagMp3EnableIndexSeeking,
          ),
        ),
      ),
    );
    _loadedRecording = path;
  }

  Future<void> _playRecording() async {
    try {
      await _ensureRecordingLoaded();
      final seg = segments[index.value];
      final pos = _player.position.inMilliseconds;
      final inside = pos >= (seg.startMs ?? 0) && pos < (seg.endMs ?? 0);
      if (!inside) {
        _seeking = true;
        try {
          await _player.seek(Duration(milliseconds: seg.startMs ?? 0));
        } finally {
          _seeking = false;
        }
      }
      await _player.setSpeed(settings.speed);
      unawaited(_player.play());
    } catch (e) {
      playing.value = false;
      error.value = 'Playback failed: $e';
      _publishState();
    }
  }

  Future<void> _seekToCurrent() async {
    _seeking = true;
    try {
      await _ensureRecordingLoaded();
      await _player.seek(
        Duration(milliseconds: segments[index.value].startMs ?? 0),
      );
    } catch (e) {
      error.value = 'Playback failed: $e';
    } finally {
      _seeking = false;
    }
  }

  /// Moves the highlight to the sentence being heard.
  void _onPosition(Duration position) {
    // While a jump is under way the player still reports the old position;
    // following it would drag the highlight back.
    if (!_recorded || !playing.value || segments.isEmpty || _seeking) return;
    final ms = position.inMilliseconds;
    var lo = 0, hi = segments.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if ((segments[mid].startMs ?? 0) <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo != index.value) {
      index.value = lo;
      _savePosition();
      _publishItem();
    }
  }

  void _recordingFinished() {
    if (!playing.value) return;
    doc?.position = segments.length; // finished
    unawaited(library.save());
    if (settings.continueToNext) {
      unawaited(
        _switchDocument(1, fromStart: true).then((moved) {
          if (!moved) {
            playing.value = false;
            _publishState();
          }
        }),
      );
      return;
    }
    playing.value = false;
    index.value = segments.length - 1;
    _publishState();
  }

  Future<void> toStart() => jumpTo(0);

  /// To the start of the last paragraph.
  Future<void> toEnd() async {
    if (segments.isEmpty) return;
    final last = segments.last.paragraph;
    await jumpTo(segments.indexWhere((s) => s.paragraph == last));
  }

  Future<bool> nextDocument() => _switchDocument(1);
  Future<bool> previousDocument() => _switchDocument(-1);

  /// Opens the document below (+1) or above (-1) in the library, keeping
  /// playback going if it was. Returns false if there isn't one.
  Future<bool> _switchDocument(int step, {bool fromStart = false}) async {
    final d = doc;
    if (d == null) return false;
    final next = library.neighbour(d, step);
    if (next == null) return false;
    final wasPlaying = playing.value;
    if (fromStart) next.position = 0;
    await open(next, await library.segmentsFor(next));
    if (wasPlaying) await play();
    return true;
  }

  Future<void> setPauses(Pauses pauses) async {
    if (pauses == settings.pauses) return;
    if (_recorded) {
      settings.pauses = pauses;
      await settings.save();
      return;
    }
    final wasPlaying = playing.value;
    await _stopPlayback();
    settings.pauses = pauses;
    await settings.save();
    _clearAudio();
    if (wasPlaying) unawaited(_loop(++_run));
  }

  Future<void> setContinueToNext(bool on) async {
    settings.continueToNext = on;
    await settings.save();
  }

  @override
  Future<void> setSpeed(double speed) async {
    settings.speed = speed;
    await settings.save();
    await _player.setSpeed(speed);
  }

  Future<void> setVoice(Voice v) async {
    if (v.id == voice.value.id) return;
    if (_recorded) {
      // A recording has its voices baked in; this applies to other documents.
      voice.value = v;
      settings.voiceId = v.id;
      await settings.save();
      return;
    }
    final wasPlaying = playing.value;
    await _stopPlayback();
    voice.value = v;
    settings.voiceId = v.id;
    await settings.save();
    _clearAudio();
    if (wasPlaying) unawaited(_loop(++_run));
  }

  Future<void> preview(Voice v) async {
    try {
      final dir = await _cache();
      final path = await tts.synth(
        'Hi, I\'m ${v.name}. This is how I\'ll sound reading your documents.',
        v,
        p.join(dir, 'preview_${v.id}.wav'),
        silenceScale: settings.pauses.silenceScale,
      );
      await _previewPlayer.setFilePath(path);
      await _previewPlayer.setSpeed(settings.speed);
      await _previewPlayer.play();
    } catch (e) {
      error.value = 'Voice preview failed: $e';
    }
  }

  // ------------------------------------------------------------ the loop

  Future<void> _loop(int run) async {
    while (run == _run && playing.value) {
      final i = index.value;
      if (i >= segments.length) {
        doc?.position = segments.length; // finished
        unawaited(library.save());
        if (settings.continueToNext) {
          // Keep going with the next document in the list.
          unawaited(
            _switchDocument(1, fromStart: true).then((moved) {
              if (!moved) {
                playing.value = false;
                _publishState();
              }
            }),
          );
          return;
        }
        playing.value = false;
        index.value = segments.length - 1;
        doc?.position = segments.length; // finished
        unawaited(library.save());
        _publishState();
        return;
      }
      _publishItem();
      final ready = _done.containsKey(_key(i));
      if (!ready) {
        waiting.value = true;
        _publishState();
      }
      final String path;
      try {
        path = await _audioFor(i);
      } catch (e) {
        if (run != _run) return;
        waiting.value = false;
        playing.value = false;
        error.value = 'Couldn\'t read that sentence aloud: $e';
        _publishState();
        return;
      }
      if (run != _run || !playing.value) return;
      waiting.value = false;
      _publishState();
      _prefetch();
      if (path.isNotEmpty) {
        _segmentDone = Completer<void>();
        try {
          await _player.setFilePath(path);
          await _player.setSpeed(settings.speed);
          if (run != _run) return;
          unawaited(_player.play());
        } catch (e) {
          if (run != _run) return;
          playing.value = false;
          error.value = 'Playback failed: $e';
          _publishState();
          return;
        }
        await _segmentDone!.future;
        if (run != _run) return;
      }
      // An explicit [pause] line in a cast document.
      if (segments[i].pauseMs > 0) {
        _segmentDone = Completer<void>();
        final timer = Timer(
          Duration(milliseconds: segments[i].pauseMs),
          _finishSegment,
        );
        await _segmentDone!.future;
        timer.cancel();
        if (run != _run) return;
      }
      // A longer pause where a paragraph or heading ends.
      final endsParagraph =
          i + 1 >= segments.length ||
          segments[i + 1].paragraph != segments[i].paragraph;
      if (endsParagraph) {
        _segmentDone = Completer<void>();
        final cast = segments[i].voiceId != null || segments[i].label != null;
        final ms =
            (cast ? settings.pauses.castLineMs : settings.pauses.paragraphMs) /
            settings.speed;
        final timer = Timer(Duration(milliseconds: ms.round()), _finishSegment);
        await _segmentDone!.future;
        timer.cancel();
        if (run != _run) return;
      }
      index.value = i + 1;
      if (index.value < segments.length) _savePosition();
    }
  }

  void _finishSegment() {
    final c = _segmentDone;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _stopPlayback() async {
    _run++;
    _finishSegment();
    waiting.value = false;
    await _player.stop();
  }

  void _savePosition() {
    final d = doc;
    if (d == null) return;
    d.position = index.value;
    unawaited(library.save());
  }

  // ------------------------------------------------------ audio generation

  String _key(int i) =>
      '${doc?.id}|${voice.value.id}|${settings.pauses.name}|$i';

  Future<String> _audioFor(int i) {
    final k = _key(i);
    final hit = _done[k];
    if (hit != null) return Future.value(hit);
    final c = Completer<String>();
    (_waiters[k] ??= []).add(c);
    _pump();
    return c.future;
  }

  void _prefetch() => _pump();

  /// Generates the earliest sentence at or after the current one that isn't
  /// ready yet, one at a time, so a jump never waits behind stale work.
  Future<void> _pump() async {
    if (_inflight != null || doc == null) return;
    final start = index.value;
    final end = min(segments.length, start + _lookAhead + 1);
    int? target;
    for (var i = start; i < end; i++) {
      if (!_done.containsKey(_key(i))) {
        target = i;
        break;
      }
    }
    if (target == null) return;
    final k = _key(target);
    _inflight = k;
    final seg = segments[target];
    // A cast line has its own voice; otherwise the one chosen in settings.
    final v = seg.voiceId != null ? voiceById(seg.voiceId) : voice.value;
    final text = forSpeech(seg.text);
    // A little extra weight on exclamations; Kokoro barely marks them.
    final emphasis = RegExp(r'!["\u201d\u2019)]*$').hasMatch(text) ? 1.15 : 1.0;
    try {
      var path = '';
      if (text.isNotEmpty) {
        final dir = await _cache();
        path = await tts.synth(
          text,
          v,
          p.join(dir, '${k.replaceAll('|', '_')}.wav'),
          silenceScale: settings.pauses.silenceScale,
          speed: seg.delivery.speed,
          gain: seg.delivery.gain * emphasis,
        );
      }
      _done[k] = path;
      for (final c in _waiters.remove(k) ?? const <Completer<String>>[]) {
        c.complete(path);
      }
    } catch (e) {
      for (final c in _waiters.remove(k) ?? const <Completer<String>>[]) {
        c.completeError(e);
      }
    } finally {
      _inflight = null;
    }
    _evict();
    unawaited(_pump());
  }

  /// Drops audio that's behind us or for another voice/doc.
  void _evict() {
    final prefix = '${doc?.id}|${voice.value.id}|${settings.pauses.name}|';
    final keep = index.value - 2;
    _done.removeWhere((k, path) {
      final stale =
          !k.startsWith(prefix) || int.parse(k.split('|').last) < keep;
      if (stale && path.isNotEmpty) {
        File(path).delete().ignore();
      }
      return stale;
    });
  }

  void _clearAudio() {
    for (final path in _done.values) {
      if (path.isNotEmpty) File(path).delete().ignore();
    }
    _done.clear();
    for (final list in _waiters.values) {
      for (final c in list) {
        if (!c.isCompleted) c.completeError(StateError('cancelled'));
      }
    }
    _waiters.clear();
  }

  // ------------------------------------------- lock screen / notification

  void _publishItem() {
    final d = doc;
    if (d == null) return;
    final total = segments.length;
    mediaItem.add(
      MediaItem(
        id: d.id,
        title: d.title,
        artist: total == 0
            ? 'Earshot'
            : 'Sentence ${index.value + 1} of $total',
        album: 'Earshot',
      ),
    );
  }

  void _publishState() {
    final isPlaying = playing.value;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.fastForward,
          MediaAction.rewind,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: waiting.value && isPlaying
            ? AudioProcessingState.loading
            : (doc == null
                  ? AudioProcessingState.idle
                  : AudioProcessingState.ready),
        playing: isPlaying,
      ),
    );
  }
}
