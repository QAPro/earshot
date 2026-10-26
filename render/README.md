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

## Files

- `setup.ps1`: the installer.
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
