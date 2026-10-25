import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:earshot/services/extract.dart';
import 'package:earshot/services/segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _docx(String bodyXml) {
  final xml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$bodyXml</w:body></w:document>';
  final a = Archive()..add(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  group('sentences', () {
    test('splits on sentence ends', () {
      expect(splitSentences('First one. Second one! Third? Yes.'),
          ['First one.', 'Second one!', 'Third?', 'Yes.']);
    });

    test('keeps abbreviations, initials and decimals together', () {
      expect(splitSentences('See e.g. the guide by J. Smith. Version 2.4 shipped.'),
          ['See e.g. the guide by J. Smith.', 'Version 2.4 shipped.']);
      expect(splitSentences('Talk to Dr. Jones about it. Then go.'),
          ['Talk to Dr. Jones about it.', 'Then go.']);
    });

    test('long sentences are cut at a comma, never mid-word', () {
      final long = List.filled(40, 'this clause runs on, and on').join(' ');
      final segs = segment(long);
      expect(segs.length, greaterThan(1));
      for (final s in segs) {
        expect(s.text.length, lessThanOrEqualTo(maxChunk));
      }
      expect(segs.map((s) => s.text).join(' ').replaceAll(RegExp(r'\s+'), ' '),
          long.replaceAll(RegExp(r'\s+'), ' '));
    });

    test('paragraph numbers follow blank lines', () {
      final segs = segment('One. Two.\n\nThree.');
      expect(segs.map((s) => s.paragraph), [0, 0, 1]);
    });
  });

  group('speech cleanup', () {
    test('URLs become "link to <site>"', () {
      expect(forSpeech('Read https://www.example.com/a/b?c=1 now.'),
          'Read link to example.com now.');
    });
    test('pure symbols say nothing', () {
      expect(forSpeech('* * *'), '');
      expect(forSpeech('---'), '');
    });
  });

  group('markdown', () {
    test('headings and list items are their own paragraphs; code skipped', () {
      final t = markdownText('# Title\nSome **bold** text\nwraps here.\n\n'
          '- item [one](http://x)\n- item two\n\n```\ncode()\n```\nEnd.');
      expect(t.split('\n\n'),
          ['Title', 'Some bold text wraps here.', 'item one', 'item two', 'End.']);
    });
  });

  group('docx', () {
    test('one paragraph per w:p, tabs as spaces, deletions dropped', () {
      final bytes = _docx('<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:tab/><w:t>world.</w:t></w:r></w:p>'
          '<w:p><w:del><w:r><w:t>gone</w:t></w:r></w:del><w:r><w:t>Second.</w:t></w:r></w:p>'
          '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>');
      expect(docxText(bytes).split('\n\n'), ['Hello world.', 'Second.', 'Cell']);
    });

    test('a non-docx file gives a readable error', () {
      expect(() => docxText(Uint8List.fromList([1, 2, 3])), throwsA(isA<ExtractException>()));
    });
  });

  group('pdf lines', () {
    test('joins wrapped lines, mends hyphens, drops page numbers', () {
      final text = pdfLinesToText([
        [
          'Introduction',
          'This is a long line of body text that wraps onto the',
          'next line and uses a hyph-',
          'enated word before it ends here.',
          'Short last line.',
          '3',
        ],
      ]);
      expect(text.split('\n\n'), [
        'Introduction',
        'This is a long line of body text that wraps onto the next line and uses a hyphenated word before it ends here. Short last line.',
      ]);
    });

    test('a paragraph continues across a page break mid-sentence', () {
      final text = pdfLinesToText([
        ['A sentence that runs to the bottom of the page and keeps going'],
        ['onto the next page.'],
      ]);
      expect(text, 'A sentence that runs to the bottom of the page and keeps going onto the next page.');
    });
  });
}
