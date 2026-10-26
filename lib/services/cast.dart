/// Multi-voice "cast" documents.
///
/// A document becomes a cast document when it starts with a cast list:
///
///     ---
///     voices:
///       Narrator: Michael
///       Boombs: Bella
///     ---
///
/// After that, each line is spoken on its own:
///
///     Boombs: Nobody goes in that water.          a character's line
///     Boombs (shouting): OUT.                     with a delivery
///     The Witch: (not looking up) It's a solvent. script-style parenthetical
///     [Boombs, whispering] Trix, no.              bracket form
///     [quietly] The rain eased.                   narrator, with a delivery
///     [pause 2s]                                  silence
///     Any other line                              the narrator
///
/// See docs/FORMAT.md for the full list.
library;

import '../voices.dart';

/// How a line should be delivered. Kokoro can't act, so a delivery maps to
/// what it *can* change: speed and loudness. The words are kept so a more
/// expressive engine can use them later.
class Delivery {
  const Delivery(this.words, {this.speed = 1.0, this.gain = 1.0});
  final String words;
  final double speed;
  final double gain;

  static const plain = Delivery('');

  static const _rules = <(List<String>, double, double)>[
    (
      [
        'whisper',
        'whispering',
        'whispered',
        'hushed',
        'murmur',
        'under her breath',
        'under his breath',
      ],
      0.92,
      0.45,
    ),
    (['quiet', 'quietly', 'soft', 'softly', 'low', 'gently'], 0.95, 0.8),
    (
      [
        'shout',
        'shouting',
        'shouted',
        'yell',
        'yelling',
        'yells',
        'scream',
        'screaming',
        'loud',
        'loudly',
        'full voice',
      ],
      1.05,
      1.6,
    ),
    (['angry', 'angrily', 'furious', 'fury', 'firm', 'commanding'], 1.02, 1.3),
    (
      [
        'excited',
        'excitedly',
        'urgent',
        'urgently',
        'fast',
        'quickly',
        'breathless',
        'panicked',
      ],
      1.12,
      1.15,
    ),
    (
      [
        'sad',
        'sadly',
        'somber',
        'tired',
        'slow',
        'slowly',
        'flat',
        'grave',
        'solemn',
      ],
      0.9,
      0.9,
    ),
    (['calm', 'calmly', 'measured', 'dry', 'drily', 'deadpan'], 0.96, 1.0),
  ];

  /// Reads free-form delivery words ("not looking up, quietly").
  factory Delivery.parse(String words) {
    final w = words.toLowerCase();
    var speed = 1.0, gain = 1.0;
    for (final (keys, s, g) in _rules) {
      if (keys.any((k) => RegExp('\\b${RegExp.escape(k)}\\b').hasMatch(w))) {
        speed *= s;
        gain *= g;
      }
    }
    return Delivery(words.trim(), speed: speed, gain: gain);
  }
}

/// One spoken line of a cast document, before sentence splitting.
class CastLine {
  const CastLine({
    required this.text,
    this.speaker,
    this.voiceId,
    this.delivery = Delivery.plain,
    this.pauseMs = 0,
  });
  final String text;
  final String? speaker; // as written, for display
  final String? voiceId; // null = the voice chosen in settings
  final Delivery delivery;
  final int pauseMs;
}

bool hasCastHeader(String text) =>
    _header(text.replaceAll('\r\n', '\n').split('\n')) != null;

/// Returns (index of first body line, name -> voice id) or null.
(int, Map<String, String>)? _header(List<String> lines) {
  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length || lines[i].trim() != '---') return null;
  i++;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length || lines[i].trim().toLowerCase() != 'voices:') {
    return null;
  }
  i++;
  final cast = <String, String>{};
  for (; i < lines.length; i++) {
    final l = lines[i].trim();
    if (l == '---') return (i + 1, cast);
    if (l.isEmpty) continue;
    // "Name: Voice" or "Name: Voice | description" (the description is for
    // the storyteller renderer; the app ignores it).
    final m = RegExp(r'^(.+?)\s*:\s*([^|\s]+)\s*(?:\|.*)?$').firstMatch(l);
    if (m == null) continue;
    final v = findVoice(m.group(2)!);
    if (v != null) cast[m.group(1)!.toLowerCase()] = v.id;
  }
  return null; // never closed
}

/// A voice by display name ("George") or id ("bm_george"), any case.
Voice? findVoice(String nameOrId) {
  final n = nameOrId.toLowerCase();
  for (final v in voices) {
    if (v.id == n || v.name.toLowerCase() == n) return v;
  }
  return null;
}

/// Parses a cast document, or returns null if [text] isn't one.
List<CastLine>? parseCast(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final h = _header(lines);
  if (h == null) return null;
  final (start, cast) = h;
  final narrator = cast['narrator'];
  final out = <CastLine>[];

  for (final raw in lines.skip(start)) {
    var line = raw.trim();
    if (line.isEmpty) continue;

    final pause = RegExp(
      r'^\[\s*pause\s*([\d.]+)\s*(ms|s)?\s*\]$',
      caseSensitive: false,
    ).firstMatch(line);
    if (pause != null) {
      final n = double.parse(pause.group(1)!);
      final ms = pause.group(2)?.toLowerCase() == 'ms' ? n : n * 1000;
      out.add(CastLine(text: '', pauseMs: ms.round().clamp(0, 30000)));
      continue;
    }

    String? speaker;
    var delivery = '';

    // [Name, delivery] text   |   [delivery] text
    final bracket = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(line);
    if (bracket != null) {
      final parts = bracket.group(1)!.split(',');
      final first = parts.first.trim();
      if (cast.containsKey(first.toLowerCase())) {
        speaker = first;
        delivery = parts.skip(1).join(',').trim();
      } else {
        delivery = bracket.group(1)!.trim();
      }
      line = bracket.group(2)!.trim();
    } else {
      // Name: text   |   Name (delivery): text
      final colon = RegExp(
        r'^([^:()\[\]]{1,40}?)\s*(?:\(([^)]*)\))?\s*:\s*(.+)$',
      ).firstMatch(line);
      if (colon != null &&
          cast.containsKey(colon.group(1)!.trim().toLowerCase())) {
        speaker = colon.group(1)!.trim();
        delivery = colon.group(2)?.trim() ?? '';
        line = colon.group(3)!.trim();
      }
    }

    // Script-style parenthetical at the start of the line: "(not looking up) It's..."
    final paren = RegExp(r'^\(([^)]*)\)\s*(.*)$').firstMatch(line);
    if (paren != null) {
      delivery = [
        delivery,
        paren.group(1)!.trim(),
      ].where((s) => s.isNotEmpty).join(', ');
      line = paren.group(2)!.trim();
    }
    if (line.isEmpty) continue;

    final voiceId = speaker != null ? cast[speaker.toLowerCase()] : narrator;
    out.add(
      CastLine(
        text: line,
        speaker: speaker,
        voiceId: voiceId,
        delivery: delivery.isEmpty ? Delivery.plain : Delivery.parse(delivery),
      ),
    );
  }
  return out;
}
