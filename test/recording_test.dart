import 'package:earshot/services/library.dart';
import 'package:flutter_test/flutter_test.dart';

/// test/fixtures/recording-script.json is a real script.json written by
/// render/render.py, so this guards the format both sides share.
void main() {
  test('a recording script loads as timed segments', () async {
    final doc = Doc(
      id: '1',
      title: 'mini-cast',
      filePath: 'unused.mp3',
      textPath: 'test/fixtures/recording-script.json',
      audioPath: 'unused.mp3',
      total: 4,
    );
    expect(doc.recorded, isTrue);
    final segs = await Library().segmentsFor(doc);
    expect(segs.length, 4);
    expect(segs[1].label, 'Ana');
    expect(segs[1].startMs, greaterThan(segs[0].endMs!));
    expect(segs[2].text, isEmpty); // the [pause 1s] line
    for (var i = 1; i < segs.length; i++) {
      expect(segs[i].startMs, greaterThanOrEqualTo(segs[i - 1].startMs!));
    }
  });

  test('recordings survive a save and reload of the library entry', () {
    final d = Doc(
      id: '2',
      title: 't',
      filePath: 'a.mp3',
      textPath: 'a.json',
      audioPath: 'a.mp3',
      total: 1,
    );
    final back = Doc.fromJson(d.toJson());
    expect(back.audioPath, 'a.mp3');
    expect(back.recorded, isTrue);
    expect(
      Doc.fromJson(
        Doc(
          id: '3',
          title: 't',
          filePath: 'x.txt',
          textPath: 'x',
          total: 1,
        ).toJson(),
      ).recorded,
      isFalse,
    );
  });
}
