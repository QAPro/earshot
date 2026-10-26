"""Renders a list of lines with one voice engine. Started by render.py.

Usage: python engine_worker.py qwen|chatterbox|chatterbox-vc jobs.json

chatterbox-vc converts already-recorded lines ("src") to a reference voice
("ref"), keeping the performance: used to keep each cast character's voice
the same from line to line.

jobs.json: [{"out": "...wav", "text": "...", ...engine options}]. Lines whose
output file already exists are skipped, so an interrupted run resumes.
Prints "DONE <n>" after each line so render.py can show progress.
"""
import json
import os
import sys
import zlib

import soundfile as sf
import torch

engine, jobs_path = sys.argv[1], sys.argv[2]
jobs = [j for j in json.load(open(jobs_path, encoding="utf-8")) if not os.path.exists(j["out"])]
print(f"TODO {len(jobs)}", flush=True)
if not jobs:
    sys.exit(0)

device = "cuda:0" if torch.cuda.is_available() else "cpu"
HERE = os.path.dirname(os.path.abspath(__file__))


def save(path, audio, sr):
    tmp = path + ".part.wav"
    sf.write(tmp, audio, sr)
    os.replace(tmp, path)  # only complete files count as done


if engine == "qwen":
    from qwen_tts import Qwen3TTSModel

    dtype = torch.bfloat16 if device.startswith("cuda") else torch.float32
    model = Qwen3TTSModel.from_pretrained("Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign", dtype=dtype, device_map=device)
    for n, j in enumerate(jobs, 1):
        # Same seed for the same character keeps their voice steadier from line to line.
        torch.manual_seed(zlib.crc32(j.get("seed_key", "").encode()))
        wavs, sr = model.generate_voice_design(text=j["text"], instruct=j["instruct"], language="English")
        save(j["out"], wavs[0], sr)
        print(f"DONE {n}", flush=True)

elif engine == "chatterbox":
    from chatterbox.tts import ChatterboxTTS

    model = ChatterboxTTS.from_pretrained(device="cuda" if device.startswith("cuda") else "cpu")
    for n, j in enumerate(jobs, 1):
        torch.manual_seed(zlib.crc32(j.get("seed_key", "").encode()))
        w = model.generate(j["text"], audio_prompt_path=os.path.join(HERE, "voices", j["voice"] + ".mp3"),
                           exaggeration=j["exaggeration"], cfg_weight=j["cfg_weight"])
        save(j["out"], w.squeeze(0).cpu().numpy(), model.sr)
        print(f"DONE {n}", flush=True)
elif engine == "chatterbox-vc":
    from chatterbox.vc import ChatterboxVC

    model = ChatterboxVC.from_pretrained(device="cuda" if device.startswith("cuda") else "cpu")
    current_ref = None
    # Grouped by character so each reference voice is prepared once.
    order = sorted(range(len(jobs)), key=lambda k: jobs[k]["ref"])
    for n, k in enumerate(order, 1):
        j = jobs[k]
        if j["ref"] != current_ref:
            model.set_target_voice(j["ref"])
            current_ref = j["ref"]
        w = model.generate(j["src"])
        save(j["out"], w.squeeze(0).cpu().numpy(), model.sr)
        print(f"DONE {n}", flush=True)
else:
    sys.exit(f"Unknown engine: {engine}")
