/// The English Kokoro v1.0 voices. `sid` is the speaker id inside the model.
class Voice {
  const Voice(this.id, this.sid, this.name, {this.recommended = false});

  final String id;
  final int sid;
  final String name;
  final bool recommended;

  bool get british => id.startsWith('b');
  bool get female => id[1] == 'f';
  String get accent => british ? 'UK' : 'US';
  String get label => '$name · $accent ${female ? 'female' : 'male'}';
}

/// The first eight are the ones Phil approved by ear (2026-10-25).
const voices = <Voice>[
  Voice('af_heart', 3, 'Heart', recommended: true),
  Voice('af_bella', 2, 'Bella', recommended: true),
  Voice('af_nicole', 6, 'Nicole', recommended: true),
  Voice('am_michael', 16, 'Michael', recommended: true),
  Voice('am_fenrir', 14, 'Fenrir', recommended: true),
  Voice('bf_emma', 21, 'Emma', recommended: true),
  Voice('bm_george', 26, 'George', recommended: true),
  Voice('bm_fable', 25, 'Fable', recommended: true),
  Voice('af_aoede', 1, 'Aoede'),
  Voice('af_kore', 5, 'Kore'),
  Voice('af_sarah', 9, 'Sarah'),
  Voice('af_nova', 7, 'Nova'),
  Voice('af_alloy', 0, 'Alloy'),
  Voice('af_sky', 10, 'Sky'),
  Voice('af_jessica', 4, 'Jessica'),
  Voice('af_river', 8, 'River'),
  Voice('am_puck', 18, 'Puck'),
  Voice('am_echo', 12, 'Echo'),
  Voice('am_eric', 13, 'Eric'),
  Voice('am_liam', 15, 'Liam'),
  Voice('am_onyx', 17, 'Onyx'),
  Voice('am_adam', 11, 'Adam'),
  Voice('bf_isabella', 22, 'Isabella'),
  Voice('bf_alice', 20, 'Alice'),
  Voice('bf_lily', 23, 'Lily'),
  Voice('bm_lewis', 27, 'Lewis'),
  Voice('bm_daniel', 24, 'Daniel'),
];

Voice voiceById(String? id) =>
    voices.firstWhere((v) => v.id == id, orElse: () => voices.first);
