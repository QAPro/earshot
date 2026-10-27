/// Splits extracted text into paragraphs and sentences, and cleans sentences
/// for speech.
library;

import 'cast.dart';

class Segment {
  const Segment(
    this.paragraph,
    this.text, {
    this.voiceId,
    this.delivery = Delivery.plain,
    this.pauseMs = 0,
    this.label,
    this.startMs,
    this.endMs,
  });

  /// Index of the paragraph this sentence belongs to.
  final int paragraph;
  final String text;

  /// Cast documents only: who speaks it (null = the voice in settings),
  /// how, an explicit silence, and the speaker name shown before a line.
  final String? voiceId;
  final Delivery delivery;
  final int pauseMs;
  final String? label;

  /// Recorded (storyteller) documents only: where this sentence sits in the
  /// audio file.
  final int? startMs;
  final int? endMs;
}

const _abbreviations = {
  'e.g',
  'i.e',
  'mr',
  'mrs',
  'ms',
  'dr',
  'vs',
  'etc',
  'fig',
  'no',
  'st',
  'jr',
  'sr',
  'inc',
  'ltd',
  'approx',
  'dept',
  'est',
  'cf',
  'al',
  'vol',
  'p',
  'pp',
  'ch',
  'sec',
  'min',
  'max',
  'jan',
  'feb',
  'mar',
  'apr',
  'jun',
  'jul',
  'aug',
  'sep',
  'sept',
  'oct',
  'nov',
  'dec',
};

/// Maximum characters per spoken chunk. Longer sentences are split at
/// commas/semicolons so the first audio arrives quickly.
const maxChunk = 320;

/// [text] has one paragraph per block separated by a blank line.
List<Segment> segment(String text) {
  final cast = parseCast(text);
  if (cast != null) return _castSegments(cast);
  final out = <Segment>[];
  final paragraphs = text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty);
  var pi = 0;
  for (final p in paragraphs) {
    for (final (piece, ms) in splitPauses(p)) {
      if (ms > 0) {
        out.add(Segment(pi, '', pauseMs: ms));
        continue;
      }
      for (final s in splitSentences(piece)) {
        for (final c in _limit(s)) {
          out.add(Segment(pi, c));
        }
      }
    }
    pi++;
  }
  return out;
}

/// A pause tag anywhere in the text: [pause 2s], [pause 500ms], [pause 1.5].
final pauseTag = RegExp(
  r'\[\s*pause\s*([\d.]+)\s*(ms|s)?\s*\]',
  caseSensitive: false,
);

/// The pause a tag asks for, in milliseconds (0–30 s).
int pauseMsOf(Match m) {
  final n = double.tryParse(m.group(1)!) ?? 0;
  final ms = m.group(2)?.toLowerCase() == 'ms' ? n : n * 1000;
  return ms.round().clamp(0, 30000);
}

/// [s] cut at its pause tags: text pieces (pause 0) and pauses (empty text),
/// in order. Blank pieces are dropped.
List<(String, int)> splitPauses(String s) {
  final out = <(String, int)>[];
  var start = 0;
  void text(String t) {
    final c = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (c.isNotEmpty) out.add((c, 0));
  }

  for (final m in pauseTag.allMatches(s)) {
    text(s.substring(start, m.start));
    final ms = pauseMsOf(m);
    if (ms > 0) out.add(('', ms));
    start = m.end;
  }
  text(s.substring(start));
  return out;
}

/// Each cast line is its own paragraph; long lines still split by sentence.
List<Segment> _castSegments(List<CastLine> lines) {
  final out = <Segment>[];
  for (var pi = 0; pi < lines.length; pi++) {
    final l = lines[pi];
    if (l.pauseMs > 0) {
      out.add(Segment(pi, '', pauseMs: l.pauseMs));
      continue;
    }
    var first = true;
    for (final (piece, ms) in splitPauses(l.text)) {
      if (ms > 0) {
        out.add(Segment(pi, '', pauseMs: ms));
        continue;
      }
      for (final s in splitSentences(piece)) {
        for (final c in _limit(s)) {
          out.add(
            Segment(
              pi,
              c,
              voiceId: l.voiceId,
              delivery: l.delivery,
              label: first ? l.speaker : null,
            ),
          );
          first = false;
        }
      }
    }
  }
  return out;
}

List<String> splitSentences(String p) {
  final result = <String>[];
  var start = 0;
  final ends = RegExp(r'''[.!?…]+["'”’)\]]*(?=\s+["'“‘(\[]?[A-Z0-9])''');
  for (final m in ends.allMatches(p)) {
    final before = p.substring(start, m.start);
    final lastWord =
        RegExp(r'([A-Za-z.]+)$').firstMatch(before)?.group(1) ?? '';
    final w = lastWord.toLowerCase();
    if (m.group(0)!.startsWith('.') &&
        (_abbreviations.contains(w) ||
            (w.length == 1 &&
                RegExp(r'[a-z]').hasMatch(w)) || // initials: "J. Smith"
            w.contains('.'))) {
      continue;
    }
    result.add(p.substring(start, m.end).trim());
    start = m.end;
  }
  final rest = p.substring(start).trim();
  if (rest.isNotEmpty) result.add(rest);
  return result;
}

Iterable<String> _limit(String s) sync* {
  var rest = s;
  while (rest.length > maxChunk) {
    final window = rest.substring(0, maxChunk);
    var cut = -1;
    for (final sep in ['; ', ': ', ', ', ' – ', ' - ', ' ']) {
      final i = window.lastIndexOf(sep);
      if (i > maxChunk ~/ 3) {
        cut = i + sep.length;
        break;
      }
    }
    if (cut < 0) cut = maxChunk;
    yield rest.substring(0, cut).trim();
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) yield rest;
}

/// What actually gets spoken: URLs shortened, symbols that read badly removed.
String forSpeech(String s) {
  var t = s;
  t = t.replaceAllMapped(
    RegExp(r'https?://(?:www\.)?([^/\s]+)\S*'),
    (m) => 'link to ${m.group(1)}',
  );
  t = t.replaceAll(RegExp(r'[•▪●◦■□►▶※†‡§¶|*_#~`^<>{}\[\]\\]'), ' ');
  t = t.replaceAll('&', ' and ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Nothing worth saying (e.g. "----" or a lone page number).
  if (!RegExp(r'[A-Za-z]').hasMatch(t) && !RegExp(r'\d{2,}').hasMatch(t)) {
    return '';
  }
  return t;
}
