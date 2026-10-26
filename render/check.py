"""Earshot render: checks one engine runs on the GPU and writes a short sample.

Usage: python check.py qwen|chatterbox
"""
import os
import sys
import time

import soundfile as sf
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ["EARSHOT_RENDER_HOME"]
OUT = os.path.join(BASE, "output")
os.makedirs(OUT, exist_ok=True)

TEXT = ("Release 4.2. Fixed: the export button no longer creates two copies of every report. "
        "Known issue: in Safari, the date picker opens behind the dialog.")
NARRATOR = ("A mature male narrator from a classic 1960s wildlife documentary: warm, measured and "
            "gently amused, slightly hushed, savouring every observation.")

engine = sys.argv[1]
if not torch.cuda.is_available():
    sys.exit("No NVIDIA GPU visible to PyTorch. Is the NVIDIA driver installed and up to date?")
gpu = torch.cuda.get_device_properties(0)
print(f"GPU: {gpu.name}, {gpu.total_memory / 2**30:.1f} GB VRAM, PyTorch {torch.__version__}")

t0 = time.time()
if engine == "qwen":
    from qwen_tts import Qwen3TTSModel
    m = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
                                      dtype=torch.bfloat16, device_map="cuda:0")
    t1 = time.time()
    wavs, sr = m.generate_voice_design(text=TEXT, instruct=NARRATOR, language="English")
    audio = wavs[0]
else:
    from chatterbox.tts import ChatterboxTTS
    m = ChatterboxTTS.from_pretrained(device="cuda")
    t1 = time.time()
    w = m.generate(TEXT, audio_prompt_path=os.path.join(HERE, "voices", "am_michael.mp3"),
                   exaggeration=0.75, cfg_weight=0.3)
    audio, sr = w.squeeze(0).cpu().numpy(), m.sr
t2 = time.time()
path = os.path.join(OUT, f"check-{engine}.mp3")
sf.write(path, audio, sr, format="MP3")
secs = len(audio) / sr
print(f"{engine}: loaded in {t1 - t0:.0f}s; {secs:.1f}s of audio in {t2 - t1:.1f}s "
      f"({secs / max(t2 - t1, 0.01):.1f}x real time). Sample: {path}")
