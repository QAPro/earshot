# Earshot storyteller renderer (Windows + NVIDIA GPU)

Turns a document into storyteller audio on a PC with an NVIDIA graphics card, for Earshot to play.

- Ordinary documents: **Chatterbox** (MIT), narrating in one of Earshot's voices.
- Cast documents ([`../docs/FORMAT.md`](../docs/FORMAT.md)): **Qwen3-TTS 1.7B VoiceDesign** (Apache-2.0),
  each line acted from the character description and delivery words.

Phil's listening test (2026-10-25) picked these: see [`../docs/PLAN.md`](../docs/PLAN.md).

## Install / update

In PowerShell (not as administrator):

```powershell
irm https://raw.githubusercontent.com/QAPro/earshot/main/render/setup.ps1 | iex
```

Installs into `D:\earshot-render` (or `%LOCALAPPDATA%\earshot-render` without a D: drive): a private
Python, two environments (the engines need different library versions), about 8 GB of models,
and an **Earshot Render** desktop shortcut. Run the same line again to update.

## Use

Drag one or more documents onto **Earshot Render** on the desktop. A window shows progress and
an estimate of the time left, then opens the output folder. For each document you get:

- `<name>.earshot`: open it in Earshot (file picker, or Share → Earshot). It plays the
  recording and still highlights, skips and remembers your place by sentence.
- `<name>.mp3`: the same audio for any player.

Ordinary documents are narrated by Chatterbox; cast documents ([`../docs/FORMAT.md`](../docs/FORMAT.md))
are acted by Qwen3-TTS. Interrupted? Drag the same file on again: finished lines are kept.

**Settings** are in `settings.json` in the install folder (created on first use):

| Setting | Meaning |
|---|---|
| `voice` | Narrator for ordinary documents: any Earshot voice name (Michael, Heart, George…) |
| `style` | `calm`, `storyteller` (default) or `dramatic` |
| `narrator` | How Qwen narrates cast documents that don't describe their Narrator |
| `output_dir` | Where results go, e.g. a Google Drive folder to reach the phone |
| `match_voices` | `true` (default): each cast character sounds the same on every line (see below) |

## How cast voices stay consistent

Qwen3-TTS builds a voice from the character description each time, so the same character
drifts a little from line to line. With `match_voices` on, the renderer:

1. has Qwen read one fixed passage per character, from their description, as that character's
   reference voice;
2. lets Qwen act every line as usual (delivery words included);
3. passes every line through Chatterbox's voice converter onto that character's reference:
   the performance stays, the voice is the same throughout.

Chosen by Phil by ear on 2026-10-26 (Blackwood and Boombs, shouting included).

## Files

- `setup.ps1`: the installer.
- `render.py`: the converter (run by the desktop shortcut). `earshot_text.py`: the same text
  rules as the app (paragraphs, sentences, cast lines). `engine_worker.py`: renders lines with
  one engine; skips lines already done.
- `check.py`: confirms an engine runs on the GPU and writes a test MP3.
- `env/*.in`: what each environment needs. `env/*.lock`: exact versions, resolved for
  Windows + CUDA 12.8 (RTX 50-series needs it). Chatterbox officially pins PyTorch 2.6, which
  doesn't support RTX 50-series; we override it to 2.8 (tested working on CPU).
  Regenerate with `uv pip compile env/qwen.in --python-version 3.12 --python-platform
  x86_64-pc-windows-msvc --extra-index-url https://download.pytorch.org/whl/cu128
  --index-strategy unsafe-best-match -o env/qwen.lock` (and the same for chatterbox with
  `--override env/chatterbox-overrides.txt`).
- `voices/`: ~9 s reference clips of each Kokoro voice. Chatterbox copies the voice from these,
  so narration sounds like the Earshot voice you chose. No real person's voice is used.
