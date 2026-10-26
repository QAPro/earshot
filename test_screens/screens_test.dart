// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders Earshot's real screens to PNG (light and dark) so the design can
// be reviewed without a phone. Not part of the CI test run.
//
//   flutter test test_screens --update-goldens
//
// Images land in test_screens/out/.
import 'dart:io';

import 'package:earshot/app_state.dart';
import 'package:earshot/audio/reader_handler.dart';
import 'package:earshot/services/library.dart';
import 'package:earshot/services/segmenter.dart';
import 'package:earshot/services/tts_worker.dart';
import 'package:earshot/ui/home_screen.dart';
import 'package:earshot/ui/player_screen.dart';
import 'package:earshot/ui/read_along.dart';
import 'package:earshot/ui/setup_screen.dart';
import 'package:earshot/ui/theme.dart';
import 'package:earshot/ui/voice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const notes = '''
Release 4.2

Fixed: the export button no longer creates two copies of every report. Fixed: filters on the issues page now survive a page refresh.

Changed: sessions now time out after thirty minutes instead of eight hours. If you work in long stretches, the app now warns you two minutes before it signs you out.

Known issue: in Safari, the date picker opens behind the dialog. A fix is planned for 4.2.1. Until then, press Escape and open the picker again.

Removed: the legacy CSV importer. Teams still using it should switch to the new import wizard before the end of the quarter.''';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

void main() {
  late AppState state;
  late ReaderHandler h;

  setUpAll(() async {
    await loadFont('Manrope', ['assets/fonts/Manrope.ttf']);
    await loadFont('Literata', ['assets/fonts/Literata.ttf']);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        '${Platform.environment['HOME']}/dev/flutter';
    await loadFont('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('earshot-screens');
    final textFile = File('${dir.path}/notes.txt')..writeAsStringSync(notes);
    final segs = segment(notes);
    state = AppState();
    final lib = state.library;
    lib.docs.addAll([
      Doc(
        id: '5',
        title: 'Release 4.2 notes',
        filePath: 'a.docx',
        textPath: textFile.path,
        total: segs.length,
        position: 9,
        chars: 21000,
      ),
      Doc(
        id: '4',
        title: 'Payments API spec v3',
        filePath: 'b.pdf',
        textPath: 'x',
        total: 200,
        position: 28,
        chars: 38000,
      ),
      Doc(
        id: '3',
        title: 'Release night',
        filePath: 'c.mp3',
        textPath: 'x',
        total: 40,
        audioPath: 'c.mp3',
        durationMs: 192000,
      ),
      Doc(
        id: '2',
        title: 'Test strategy — mobile',
        filePath: 'd.docx',
        textPath: 'x',
        total: 120,
        chars: 14000,
      ),
      Doc(
        id: '1',
        title: 'Onboarding guide',
        filePath: 'e.md',
        textPath: 'x',
        total: 50,
        position: 50,
        chars: 6000,
      ),
    ]);
    state.settings.speed = 1.25;
    state.settings.voiceId = 'af_heart';
    h = ReaderHandler(TtsWorker('/nonexistent'), lib, state.settings);
    state.handlerForTest = h;
    h.doc = lib.docs.first;
    h.segments = segs;
    h.index.value = 9;
    h.playing.value = true;
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Size size = const Size(390, 844),
    Future<void> Function()? then,
  }) async {
    debugDisableShadows = false; // real shadows, not test outlines
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final dpr = size.width > 600 ? 1.5 : 3.0;
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: earshotTheme(Brightness.light),
          darkTheme: earshotTheme(Brightness.dark),
          themeMode: mode,
          home: screen,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      if (then != null) await then();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/$name-${mode.name}.png'),
      );
    }
    debugDisableShadows = true;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'library',
    (t) => shoot(t, '1-library', HomeScreen(state: state)),
  );

  testWidgets(
    'player',
    (t) => shoot(t, '2-player', PlayerScreen(state: state)),
  );

  testWidgets(
    'read along',
    (t) => shoot(t, '3-read-along', ReadAlongScreen(state: state)),
  );

  testWidgets(
    'voice sheet',
    (t) => shoot(
      t,
      '4-voice-and-pace',
      PlayerScreen(state: state),
      then: () async {
        showVoiceSheet(t.element(find.byType(PlayerScreen)), h);
        await t.pumpAndSettle();
      },
    ),
  );

  testWidgets(
    'setup',
    (t) => shoot(t, '5-first-run', SetupScreen(onDone: () async {})),
  );

  testWidgets(
    'windows player',
    (t) => shoot(
      t,
      '6-windows-player',
      PlayerScreen(state: state),
      size: const Size(1280, 800),
    ),
  );
}
