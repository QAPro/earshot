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
- Tone/style control (heavier model on the 5080)
- OCR for scanned PDFs

## Feedback loop

Phil uses it, tells Claude what's wrong or missing; each item becomes a GitHub issue and a fix.
