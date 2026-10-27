"""Earshot storyteller renderer: turns documents into audio for Earshot.

Usage (or drag files onto the "Earshot Render" desktop shortcut):
    earshot-render.cmd report.docx notes.md scene.txt

- Ordinary documents are narrated by Chatterbox in an Earshot voice.
- Cast documents (see docs/FORMAT.md) are acted line by line by Qwen3-TTS.

For each document it writes, into the output folder:
    <name>.mp3       plays anywhere
    <name>.earshot   open in Earshot: the audio plus the text, with sentence
                     timings, so the reader highlights and skips as usual

Settings: settings.json next to the output folder (created on first run).
Interrupted? Run it again on the same file; finished lines are kept.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import zipfile

import numpy as np
import soundfile as sf

import earshot_text as et

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("EARSHOT_RENDER_HOME", os.path.dirname(HERE))
SR = 24000

DEFAULTS = {
    "_help": "Edit and save; used for every document. voice: any Earshot voice name (Michael, Heart, "
             "George...). style: calm | storyteller | dramatic. narrator: how Qwen should sound when it "
             "narrates (cast documents without a Narrator description). output_dir: where results go. "
             "match_voices: true keeps each cast character's voice the same on every line.",
    "voice": "Michael",
    "style": "storyteller",
    "narrator": "A warm, expressive audiobook narrator with a clear voice, measured and engaging, "
                "bringing the text to life without overacting",
    "output_dir": os.path.join(BASE, "output"),
    "match_voices": True,
}
# Read by each character once to fix their voice; every line is then matched to it.
REF_TEXT = ("I'll tell you exactly what happened, from the beginning, and I'll try to "
            "leave nothing out, because the details matter more than anyone thinks.")
STYLES = {  # Chatterbox: exaggeration, cfg_weight (lower = more expressive pacing)
    "calm": (0.4, 0.5),
    "storyteller": (0.75, 0.3),
    "dramatic": (1.0, 0.25),
}
# Gaps the renderer adds between clips (each clip is trimmed of its own silence).
GAP_SENTENCE_MS = 250
GAP_PARAGRAPH_MS = 700
GAP_CAST_LINE_MS = 250

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def settings() -> dict:
    path = os.path.join(BASE, "settings.json")
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(DEFAULTS, f, indent=2)
        print(f"Created settings: {path}")
    with open(path, encoding="utf-8") as f:
        s = {**DEFAULTS, **json.load(f)}
    if not et.find_voice(s["voice"]):
        print(f"Unknown voice '{s['voice']}' in settings.json; using Michael.")
        s["voice"] = "Michael"
    if s["style"] not in STYLES:
        print(f"Unknown style '{s['style']}' in settings.json; using storyteller.")
        s["style"] = "storyteller"
    return s


def python_for(engine: str) -> str:
    env = os.path.join(BASE, "envs", "chatterbox" if engine.startswith("chatterbox") else engine)
    win = os.path.join(env, "Scripts", "python.exe")
    return win if os.path.exists(win) else os.path.join(env, "bin", "python")


def chatterbox_tuning(style: str, delivery: str) -> tuple[float, float]:
    ex, cfg = STYLES[style]
    d = delivery.lower()
    if re.search(r"\b(shout|yell|scream|furious|angry|excited|urgent|panicked)", d):
        ex, cfg = min(ex + 0.3, 1.3), max(cfg - 0.05, 0.2)
    if re.search(r"\b(whisper|quiet|soft|gentl|hushed|calm|flat|dry)", d):
        ex = max(ex - 0.25, 0.25)
    return ex, cfg


def qwen_who(seg: et.Segment, s: dict) -> str:
    """Who is speaking, for Qwen: the cast description, else a plain one."""
    if seg.description:
        who = seg.description
    elif seg.label or seg.voice:
        who = et.describe_voice(seg.voice or et.find_voice(s["voice"]))
    else:
        who = s["narrator"]
    return who.rstrip(". ")


def qwen_instruct(seg: et.Segment, s: dict) -> str:
    who = qwen_who(seg, s)
    return f"{who}. Delivery: {seg.delivery}." if seg.delivery else f"{who}."


def run_engine(engine: str, jobs: list[dict], work: str) -> None:
    path = os.path.join(work, f"jobs-{engine}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(jobs, f, ensure_ascii=False)
    cmd = [python_for(engine), "-u", os.path.join(HERE, "engine_worker.py"), engine, path]
    label = {"qwen": "Qwen3-TTS", "chatterbox": "Chatterbox",
             "chatterbox-vc": "Voice matching"}[engine]
    print(f"Loading {label}...", flush=True)
    t0 = time.time()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace")
    todo, first_done, log = 0, None, []
    for line in proc.stdout:
        line = line.rstrip()
        if line.startswith("TODO "):
            todo = int(line.split()[1])
            if todo:
                print(f"{todo} lines to record ({len(jobs) - todo} already done).", flush=True)
        elif line.startswith("DONE "):
            n = int(line.split()[1])
            now = time.time()
            first_done = first_done or now
            # About every 10%, plus the first and last line, not every line.
            step = max(1, todo // 10)
            if n not in (1, todo) and n % step:
                continue
            eta = ""
            if 1 < n < todo:
                per = (now - first_done) / (n - 1)
                left = per * (todo - n)
                eta = f", about {int(left // 60)} min {int(left % 60)} s left"
            print(f"  {n}/{todo} ({100 * n // todo}%){eta}", flush=True)
        else:
            log.append(line)
    if proc.wait() != 0:
        print("\n".join(log[-25:]))
        raise SystemExit(f"{label} stopped with an error (see above). Finished lines are kept; run again to resume.")
    print(f"{label} finished in {int(time.time() - t0)} s.", flush=True)


def trim(x: np.ndarray, threshold: float = 0.01) -> np.ndarray:
    idx = np.where(np.abs(x) > threshold)[0]
    if len(idx) == 0:
        return x[:0]
    pad = int(SR * 0.03)
    return x[max(idx[0] - pad, 0): idx[-1] + pad]


def load(path: str) -> np.ndarray:
    x, sr = sf.read(path, dtype="float32", always_2d=False)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        n = int(len(x) * SR / sr)
        x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype("float32")
    return x


def render(path: str, s: dict) -> None:
    name = os.path.splitext(os.path.basename(path))[0]
    print(f"\n=== {name}", flush=True)
    text = et.extract_text(path)
    segs = et.segment(text)
    cast = any(x.cast for x in segs)
    engine = "qwen" if cast else "chatterbox"
    voice = et.find_voice(s["voice"])

    # One work folder per document version + settings, so reruns resume.
    key = hashlib.sha1(json.dumps([text, engine, s["voice"], s["style"], s["narrator"]]).encode()).hexdigest()[:12]
    work = os.path.join(BASE, "work", f"{re.sub(r'[^A-Za-z0-9_-]+', '_', name)[:40]}-{key}")
    os.makedirs(work, exist_ok=True)

    jobs, clip = [], {}
    for i, seg in enumerate(segs):
        spoken = et.for_speech(seg.text)
        if not spoken:
            continue
        out = os.path.join(work, f"seg_{i:05d}.wav")
        clip[i] = out
        if engine == "qwen":
            jobs.append({"out": out, "text": spoken, "instruct": qwen_instruct(seg, s),
                         "seed_key": seg.speaker or "narrator"})
        else:
            ex, cfg = chatterbox_tuning(s["style"], seg.delivery)
            jobs.append({"out": out, "text": spoken, "voice": seg.voice or voice,
                         "exaggeration": ex, "cfg_weight": cfg, "seed_key": "narrator"})
    # Cast documents: one reference clip per character, designed once from their
    # description, so every line can be matched to the same voice afterwards.
    match = cast and bool(s.get("match_voices", True))
    refs: dict[str, str] = {}
    if match:
        for i, seg in enumerate(segs):
            # Every sentence of a line belongs to its speaker, not just the first.
            k = seg.speaker or "narrator"
            if i not in clip or k in refs:
                continue
            refs[k] = os.path.join(work, f"ref_{re.sub(r'[^A-Za-z0-9]+', '_', k)[:30]}.wav")
            jobs.insert(0, {"out": refs[k], "text": REF_TEXT, "instruct": qwen_who(seg, s) + ".", "seed_key": k})
    kind = "cast document, acted by Qwen3-TTS" if cast else f"narrated by Chatterbox as {s['voice']} ({s['style']})"
    print(f"{len(segs)} sentences, {kind}" + (f"; {len(refs)} voices kept consistent." if match else "."), flush=True)
    run_engine(engine, jobs, work)
    if match:
        vc_jobs = []
        for i, seg in enumerate(segs):
            if i in clip:
                k = seg.speaker or "narrator"
                # The speaker is in the name, so a change of speaker re-matches.
                slug = re.sub(r"[^A-Za-z0-9]+", "_", k)[:30]
                matched = clip[i].replace(".wav", f".matched-{slug}.wav")
                vc_jobs.append({"src": clip[i], "ref": refs[k], "out": matched})
                clip[i] = matched
        run_engine("chatterbox-vc", vc_jobs, work)

    # Assemble: trimmed clips with our own gaps, and each sentence's timing.
    parts, timeline, pos = [], [], 0

    def add(x: np.ndarray):
        nonlocal pos
        parts.append(x)
        pos += len(x)

    for i, seg in enumerate(segs):
        start = pos
        if seg.pause_ms:
            add(np.zeros(int(SR * seg.pause_ms / 1000), dtype="float32"))
        elif i in clip:
            add(trim(load(clip[i])))
        end = pos
        nxt = segs[i + 1] if i + 1 < len(segs) else None
        if nxt is not None:
            if nxt.paragraph == seg.paragraph:
                gap = GAP_SENTENCE_MS
            else:
                gap = GAP_CAST_LINE_MS if cast else GAP_PARAGRAPH_MS
            add(np.zeros(int(SR * gap / 1000), dtype="float32"))
        timeline.append({"paragraph": seg.paragraph, "text": seg.text, "label": seg.label,
                         "start": int(start * 1000 / SR), "end": int(end * 1000 / SR)})
    audio = np.concatenate(parts) if parts else np.zeros(SR, dtype="float32")
    peak = float(np.abs(audio).max()) or 1.0
    audio = (audio * min(0.9 / peak, 4.0)).astype("float32")

    out_dir = s["output_dir"]
    os.makedirs(out_dir, exist_ok=True)
    mp3 = os.path.join(out_dir, f"{name}.mp3")
    # Constant bitrate: players seek to an exact time, so the highlighted
    # sentence stays in step after a jump (variable bitrate drifted).
    sf.write(mp3, audio, SR, format="MP3", bitrate_mode="CONSTANT", compression_level=0.5)
    script = {
        "format": "earshot-audio", "version": 1, "title": name, "source": os.path.basename(path),
        "engine": engine, "voice": None if cast else s["voice"], "style": None if cast else s["style"],
        "created": dt.datetime.now().isoformat(timespec="seconds"),
        "durationMs": int(len(audio) * 1000 / SR), "segments": timeline,
    }
    pkg = os.path.join(out_dir, f"{name}.earshot")
    with zipfile.ZipFile(pkg, "w") as z:
        z.write(mp3, "audio.mp3", compress_type=zipfile.ZIP_STORED)
        z.writestr("script.json", json.dumps(script, ensure_ascii=False, indent=1))
    mins = len(audio) / SR / 60
    print(f"Done: {mins:.1f} minutes of audio.\n  {pkg}\n  {mp3}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser(description="Turn documents into storyteller audio for Earshot.")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    if not args.files:
        print("Drag one or more documents (PDF, Word, text, Markdown) onto the Earshot Render shortcut.")
        return
    s = settings()
    failed = []
    for f in args.files:
        if not f.lower().endswith(et.SUPPORTED):
            print(f"\nSkipping {os.path.basename(f)}: not a PDF, Word, text or Markdown file.")
            continue
        try:
            render(f, s)
        except (ValueError, OSError) as e:
            print(f"Couldn't convert {os.path.basename(f)}: {e}")
            failed.append(f)
    if sys.platform == "win32" and len(failed) < len(args.files):
        os.startfile(s["output_dir"])  # show the results


if __name__ == "__main__":
    main()
