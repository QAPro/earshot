# Earshot

Reads your documents aloud, offline, with natural-sounding voices.
Android and Windows. PDF, Word (.docx), text and Markdown.

- Voices: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache-2.0), run on-device through
  [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache-2.0).
- Nothing leaves your device. The only network use is a one-time download of the voices (~350 MB).

## Install

Get the latest build from [Releases](https://github.com/QAPro/earshot/releases/latest).

- **Android:** download `earshot-android.apk` on the phone and open it. Allow your browser to
  install apps when asked.
- **Windows:** download `earshot-windows.zip`, unzip it anywhere, run `earshot.exe`. Windows
  SmartScreen will warn about an unknown publisher: *More info → Run anyway*.

## Use

Open a document (or Share one to Earshot), pick a voice and speed, press play. It keeps
reading with the screen off; use the lock screen or your headset buttons.

See [`docs/PLAN.md`](docs/PLAN.md) for what's planned.
