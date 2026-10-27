import 'dart:io';

import 'package:earshot/services/cast.dart';
import 'package:earshot/services/segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

const doc = '''
---
voices:
  Narrator: Michael
  Boombs: Bella | strong woman, late thirties, calm authority
  The Witch: emma
  Ghost: NoSuchVoice
---
Rain on the embankment.
Boombs: Nobody goes in that water.
Boombs (shouting): OUT. Everybody out, now!
The Witch: (not looking up, dry) It's a solvent.
[Boombs, whispering] Trix, no.
[quietly] The rain eased.
[pause 2s]
Note: this line is not a character.
''';

void main() {
  test('normal documents are not cast documents', () {
    expect(parseCast('Note: hello.\n\nAnother paragraph.'), isNull);
    expect(hasCastHeader('---\ntitle: x\n---\nText'), isFalse);
  });

  test('cast list maps names to voices; unknown voices are ignored', () {
    final lines = parseCast(doc)!;
    expect(lines.first.voiceId, 'am_michael'); // narrator
    expect(lines[1].speaker, 'Boombs');
    expect(lines[1].voiceId, 'af_bella');
    expect(lines[3].voiceId, 'bf_emma'); // voice names are case-insensitive
  });

  test('deliveries from parentheses, brackets and script parentheticals', () {
    final l = parseCast(doc)!;
    expect(l[2].delivery.gain, greaterThan(1.3)); // shouting
    expect(l[3].text, "It's a solvent.");
    expect(l[3].delivery.words, 'not looking up, dry');
    expect(l[4].speaker, 'Boombs');
    expect(l[4].delivery.gain, lessThan(0.6)); // whispering
    expect(l[5].speaker, isNull);
    expect(l[5].delivery.words, 'quietly');
    expect(l[5].text, 'The rain eased.');
  });

  test('pauses, and "Name:" only counts for names in the cast', () {
    final l = parseCast(doc)!;
    expect(l[6].pauseMs, 2000);
    expect(l[7].speaker, isNull);
    expect(l[7].text, 'Note: this line is not a character.');
  });

  test('segments carry voice, delivery and the speaker label once per line', () {
    final segs = segment(doc);
    final boombs = segs.where((s) => s.voiceId == 'af_bella').toList();
    expect(boombs.first.label, 'Boombs');
    // "OUT. Everybody out, now!" is two sentences; only the first is labelled.
    final shout = segs
        .where(
          (s) => s.text.startsWith('OUT') || s.text.startsWith('Everybody'),
        )
        .toList();
    expect(shout.length, 2);
    expect(shout[0].label, 'Boombs');
    expect(shout[1].label, isNull);
    expect(segs.any((s) => s.pauseMs == 2000 && s.text.isEmpty), isTrue);
  });

  test('the example cast file parses with every speaker cast', () {
    final f = File('docs/samples/cast-example.txt');
    final lines = parseCast(f.readAsStringSync())!;
    expect(lines.length, greaterThan(5));
    expect(lines.where((l) => l.speaker != null && l.voiceId == null), isEmpty);
  });

  test('pause tags work inside a line and in plain documents', () {
    const doc = '''---
voices:
  Narrator: George
  Jo: Heart
---
Jo: Yeah, well. [pause 2s] Fine.
[pause 500ms] The door shut.''';
    final segs = segment(doc);
    expect(segs.map((s) => s.text).toList(), [
      'Yeah, well.',
      '',
      'Fine.',
      '',
      'The door shut.',
    ]);
    expect(segs[1].pauseMs, 2000);
    expect(segs[3].pauseMs, 500);
    expect(segs[0].label, 'Jo');
    expect(segs[2].label, isNull); // label once per line
    expect(segs[2].voiceId, 'af_heart'); // still Jo after the pause
    expect(segs[4].label, isNull); // narrator, not a delivery note

    final plain = segment(
      'First part. [Pause 1.5s] Second part.\n\n[pause 3s]',
    );
    expect(plain.map((s) => (s.text, s.pauseMs)).toList(), [
      ('First part.', 0),
      ('', 1500),
      ('Second part.', 0),
      ('', 3000),
    ]);
  });
}
