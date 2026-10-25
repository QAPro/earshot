# Earshot — plan

*Started 2026-10-25.*

## Why

Phil wants to listen to documentation while doing low-attention manual work (common in
testing): keep up with docs and learn while getting other work done. Existing options were
rejected: the free Android voices sounded bad, and the best reader app is full of adware.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Voices | Kokoro-82M v1.0, on-device | Phil compared samples by ear on 2026-10-25: "MUCH better" than anything else he'd heard. Small enough for a phone. Apache-2.0. |
| Where it runs | Fully offline after a one-time ~350 MB voice download | Free, private, works anywhere. |
| Framework | Flutter | One codebase for Android and Windows; sherpa-onnx has official Flutter support for both. |
| Distribution | GitHub releases, installed directly (no Play Store) | €0. |
| Model delivery | Downloaded on first launch, not bundled | Keeps each app update ~40 MB instead of ~400 MB while Phil iterates. |
| Speed control | Player speed (pitch-preserving), not re-generation | Changes apply instantly. |

## Done since v1 (2026-10-25)

- Previous/next document, start/end of document, optional continue-to-next.
- Pauses fixed: sherpa-onnx defaulted `silence_scale` to 0.2 (≈200 ms at every stop);
  Natural is 0.6 (≈520–620 ms, matching reference Kokoro). Extra pause per paragraph.
- Cast documents: several voices, delivery words, `[pause]` lines — see [`FORMAT.md`](FORMAT.md).

## Expressive / storyteller reading — research (2026-10-25)

**Why Phil wants it:** a storyteller voice makes any document easier to remember. A software
architect he worked with read release notes aloud as a wildlife-documentary narrator; every
mistake was crystal clear and memorable.

**What Kokoro can and can't do:**
- `?` and `!` do reach the model (token ids 6 and 5 in sherpa-onnx's Kokoro), but Kokoro's
  response is mild: a slight lift on questions, little on exclamations.
- No emotion or style control. Deliveries in cast documents are approximated with speed and
  loudness only.
- No phone-sized sherpa-onnx model with emotion/style control was found (2026-10).

**Expressive models (need a GPU → the 5080; render a document to audio ahead of time):**

| Model | Control | Licence | Notes |
|---|---|---|---|
| Qwen3-TTS 1.7B VoiceDesign | Plain-English voice + delivery description per line | Apache-2.0 (checked on the HF model card) | ~6–8 GB VRAM. Voice can drift between lines; for a consistent character, design once then clone with the Base model. |
| Qwen3-TTS 1.7B CustomVoice | Fixed voices + instruction | Apache-2.0 | Only two native English voices (Ryan, Aiden), both male. |
| Chatterbox (Resemble AI) | Emotion "exaggeration" slider; clones a voice from ~5 s of audio | MIT | Turbo variant adds `[laugh]`-style tags. Reference audio can be a Kokoro clip (no real person cloned). |
| IndexTTS-2 | Strongest emotion control (separate voice and emotion) | Custom, non-commercial | Not tested. |
| Orpheus 3B | Inline tags (`<laugh>`, `<sigh>`) | Open | Not tested. |

**Listening test result (Phil, 2026-10-25), same passages on all three:**
- **Straight narration (release notes): Chatterbox** was best.
- **Drama (AMARANTH cast scene): Qwen3-TTS VoiceDesign** was the clear winner: best variety of
  voices, best emotion and range.
- So: Chatterbox renders ordinary documents; Qwen renders cast documents.

## Version 1 (basic)

- Open PDF (single column), Word .docx, .txt, .md — file picker, Share, or Open with.
- Google Docs: Share & export → Send a copy → Word/PDF → Earshot.
- Voice picker with preview; speed 0.75×–2×.
- Plays with the screen off; lock-screen, notification and headset controls.
- Skip sentence / paragraph; tap a sentence to jump there.
- Remembers the position in every document.

## Later (only if Phil asks after using it)

- Multi-column PDFs
- EPUB
- Opening Google Docs directly
- Saving a document as MP3
- OCR for scanned PDFs

## Feedback loop

Phil uses it, tells Claude what's wrong or missing; each item becomes a GitHub issue and a fix.
