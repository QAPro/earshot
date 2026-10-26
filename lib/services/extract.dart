/// Turns a document file into plain text: one paragraph per block,
/// blocks separated by a blank line.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import 'cast.dart';

const supportedExtensions = [
  'pdf',
  'docx',
  'txt',
  'md',
  'markdown',
  'text',
  'earshot', // storyteller recording from render/render.py
];

class ExtractException implements Exception {
  ExtractException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<String> extractText(String path) async {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  final String text;
  switch (ext) {
    case 'pdf':
      text = await _pdf(path);
    case 'docx':
      text = docxText(await File(path).readAsBytes());
    case 'md':
    case 'markdown':
      final raw = _decode(await File(path).readAsBytes());
      // A cast document keeps its lines exactly as written.
      text = hasCastHeader(raw) ? raw : markdownText(raw);
    default:
      text = plainText(_decode(await File(path).readAsBytes()));
  }
  if (text.trim().isEmpty) {
    throw ExtractException(
      ext == 'pdf'
          ? 'No readable text in this PDF. It may be a scanned image.'
          : 'No readable text found in this file.',
    );
  }
  return text;
}

String _decode(Uint8List bytes) => decodeText(bytes);

/// Text files from Windows can be UTF-8 (with or without a byte-order mark)
/// or UTF-16 (Notepad's "Unicode", older PowerShell output).
String decodeText(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  bool? littleEndian;
  var start = 0;
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    littleEndian = true;
    start = 2;
  } else if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    littleEndian = false;
    start = 2;
  } else if (b.length >= 8) {
    // No marker: UTF-16 still shows up as lots of zero bytes on one side.
    final n = b.length.clamp(0, 2000) & ~1;
    var evenZeros = 0, oddZeros = 0;
    for (var i = 0; i < n; i += 2) {
      if (b[i] == 0) evenZeros++;
      if (b[i + 1] == 0) oddZeros++;
    }
    if (oddZeros > n / 4 && evenZeros == 0) littleEndian = true;
    if (evenZeros > n / 4 && oddZeros == 0) littleEndian = false;
  }
  if (littleEndian == null) return utf8.decode(b, allowMalformed: true);
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Plain text. Blank lines separate paragraphs. If the file has no blank
/// lines but long lines, each line is a paragraph.
String plainText(String s) {
  final t = s.replaceAll('\r\n', '\n');
  if (RegExp(r'\n\s*\n').hasMatch(t)) return t;
  final lines = t.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return '';
  final avg = lines.fold<int>(0, (a, l) => a + l.length) / lines.length;
  return avg > 90 ? lines.join('\n\n') : t;
}

/// Markdown: headings, list items and quotes become their own paragraphs;
/// formatting symbols are dropped; code blocks are skipped.
String markdownText(String s) {
  final out = <String>[];
  final buf = StringBuffer();
  var inCode = false;
  void flush() {
    if (buf.isNotEmpty) out.add(buf.toString().trim());
    buf.clear();
  }

  for (var line in s.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trimLeft().startsWith('```') ||
        line.trimLeft().startsWith('~~~')) {
      inCode = !inCode;
      flush();
      continue;
    }
    if (inCode) continue;
    final trimmed = line.trim();
    if (trimmed.isEmpty ||
        RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      flush();
      continue;
    }
    if (RegExp(r'^\|?\s*:?-{3,}').hasMatch(trimmed)) continue; // table divider
    final block = RegExp(r'^(#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s?)')
        .firstMatch(trimmed);
    if (block != null) {
      flush();
      line = trimmed.substring(block.end);
    }
    line = line
        .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'[*_`]{1,3}'), '')
        .replaceAll('|', ', ');
    buf.write('${line.trim()} ');
    if (block != null && block.group(0)!.startsWith('#')) flush();
  }
  flush();
  return out.where((p) => p.isNotEmpty).join('\n\n');
}

/// Word .docx: one paragraph per `w:p` element, including table cells.
String docxText(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw ExtractException('This doesn\'t look like a Word (.docx) file.');
  }
  final file = archive.findFile('word/document.xml');
  if (file == null) throw ExtractException('No document body in this .docx.');
  final doc = XmlDocument.parse(
    utf8.decode(file.content, allowMalformed: true),
  );
  final paragraphs = <String>[];
  final buf = StringBuffer();

  void walk(XmlNode node) {
    for (final child in node.children) {
      if (child is! XmlElement) continue;
      switch (child.name.qualified) {
        case 'w:p':
          if (buf.isNotEmpty) paragraphs.add(buf.toString());
          buf.clear();
          walk(child);
          if (buf.isNotEmpty) paragraphs.add(buf.toString());
          buf.clear();
        case 'w:t':
          buf.write(child.innerText);
        case 'w:tab':
        case 'w:br':
        case 'w:cr':
          buf.write(' ');
        case 'w:del': // tracked deletions are not part of the text
        case 'w:instrText': // field codes
          break;
        default:
          walk(child);
      }
    }
  }

  walk(doc.rootElement);
  return paragraphs
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join('\n\n');
}

Future<String> _pdf(String path) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  try {
    final pageLines = <List<String>>[];
    for (final page in doc.pages) {
      final t = await page.loadStructuredText();
      pageLines.add(t.fullText.split(RegExp(r'\r?\n')));
    }
    return pdfLinesToText(pageLines);
  } finally {
    await doc.dispose();
  }
}

/// Rebuilds paragraphs from PDF lines: joins wrapped lines, mends
/// hyphenation, drops bare page numbers, and breaks a paragraph after a short
/// line that ends a sentence.
String pdfLinesToText(List<List<String>> pages) {
  final paragraphs = <String>[];
  final buf = StringBuffer();
  void flush() {
    final s = buf.toString().trim();
    if (s.isNotEmpty) paragraphs.add(s);
    buf.clear();
  }

  for (final raw in pages) {
    final lines = raw.map((l) => l.trim()).toList();
    final widths =
        lines.where((l) => l.isNotEmpty).map((l) => l.length).toList()..sort();
    final typical = widths.isEmpty
        ? 0
        : widths[(widths.length * 0.8).floor().clamp(0, widths.length - 1)];
    for (final line in lines) {
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (RegExp(
        r'^(page\s*)?\d+(\s*(of|/)\s*\d+)?$',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      final s = buf.toString();
      if (s.endsWith('-') && RegExp(r'^[a-z]').hasMatch(line)) {
        buf.clear();
        buf.write(s.substring(0, s.length - 1));
        buf.write(line);
      } else {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(line);
      }
      final endsSentence = RegExp(r'''[.!?:]["'”’)]*$''').hasMatch(line);
      // A short standalone line with no closing punctuation is a heading.
      final heading =
          s.isEmpty &&
          !endsSentence &&
          line.length < typical * 0.6 &&
          RegExp(r'^[A-Z0-9]').hasMatch(line);
      if (heading || (endsSentence && line.length < typical * 0.75)) flush();
    }
    // A page break only ends a paragraph if the last line ended a sentence.
    if (RegExp(r'''[.!?:]["'”’)]*$''').hasMatch(buf.toString())) flush();
  }
  flush();
  return paragraphs.join('\n\n');
}
