# Earshot

Offline read-aloud app for Phil's documents (PDF, Word .docx, text, Markdown) on
Android (Galaxy S25, Android 17) and Windows 11. Purpose: listen to documentation
while doing low-attention manual work. Free, personal tool first; public repo.
Plan and decisions: [`docs/PLAN.md`](docs/PLAN.md).

## Stack

- **Flutter 3.47.8** (Dart), one codebase for Android + Windows.
- **Voices:** Kokoro-82M v1.0 via **sherpa_onnx 1.13.8** (on-device). The model is
  *not* in the app: it downloads once on first launch from this repo's
  `model-kokoro-en-v1.0` release (zip + SHA-256 checked in `lib/services/model_manager.dart`).
- **Playback:** just_audio (+ just_audio_windows), audio_service for Android
  lock-screen/headset controls and background playback.
- **Docs:** pdfrx (PDF text), archive + xml (.docx), own Markdown/text handling.

## Layout

- `lib/services/extract.dart` — file → plain text (one paragraph per blank-line block)
- `lib/services/segmenter.dart` — paragraphs → sentences; `forSpeech` cleanup
- `lib/services/tts_worker.dart` — Kokoro on a background isolate, one request at a time
- `lib/audio/reader_handler.dart` — the reading loop: generates ~3 sentences ahead, plays, saves position
- `lib/ui/` — setup (voice download), home (library), reader, voice/speed sheet
- `android/.../MainActivity.kt` — receives Share / Open-with, copies the file, sends the path to Dart

## Commands (on the VPS)

Tools live in the home folder, not on PATH:

```bash
export PATH=~/dev/flutter/bin:~/dev/jdk21/bin:$PATH JAVA_HOME=~/dev/jdk21
flutter analyze && flutter test           # the feedback loop
flutter build apk --release --target-platform android-arm64
```

Windows builds only happen in GitHub Actions (Flutter can't cross-compile to Windows).

## Releases

Every push to `main` runs `.github/workflows/build.yml`: test → Android APK + Windows zip →
GitHub release `build-N` (marked latest). Phil installs from
https://github.com/QAPro/earshot/releases/latest.

**Signing:** the release key is at `~/.config/earshot/` (keystore + `key.properties`), mirrored
in repo secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEY_PASSWORD`. **Never lose or rotate it** —
a different key means Android refuses the update and Phil must uninstall (losing his library).

## Conventions

- Issues are GitHub Issues; Phil's usage feedback becomes issues. Follow ExecAssist's
  side-project rules (`~/ExecAssist/.claude/rules/side-project-workflow.md`).
- Voice ids/speaker ids are in `lib/voices.dart`; the first eight are the ones Phil approved.
- British voices need lexicon `lexicon-gb-en.txt` and eSpeak language `en` (not `en-gb`, which fails).
- **Android resources referenced by name at runtime must be listed in `res/raw/keep.xml`.** The
  release shrinker deletes them otherwise, and a missing notification icon kills the app on Play
  (issue #1). Check with `aapt2 dump resources <apk> | grep <name>`.
- Phil can't send logcat. A crash shows up on the next launch with a Copy button; ask him to paste it.
- Pin dependency versions; prefer releases at least two weeks old.
