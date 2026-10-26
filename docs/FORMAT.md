# Earshot cast format — voices, delivery and pauses

Any document can be read by several voices. You turn it on by starting the
document with a **cast list**. Documents without one are read normally, so
nothing changes for ordinary docs.

Works in `.txt`, `.md` and Word `.docx` files. In Word, put each line in its
own paragraph.

A complete example: [`samples/cast-example.txt`](samples/cast-example.txt).

---

## 1. The cast list

The very first lines of the document:

```
---
voices:
  Narrator: Michael
  Ana: Heart
  Tom: George
---
```

- One line per character: `Name: Voice`.
- `Narrator` reads every line that isn't given to a character. Leave it out and
  the narrator is whatever voice you picked in the app.
- Names can have spaces (`The Witch: Emma`). Upper/lower case doesn't matter.
- A voice name Earshot doesn't know is ignored; that character falls back to
  the narrator.
- **Optional, for storyteller recordings:** add `| description` after the voice
  to tell the storyteller engine who the character is. The app ignores it.

  ```
  Boombs: Bella | a strong woman in her late thirties, a structural engineer, calm authority
  Narrator: Michael | a warm, gently amused wildlife-documentary narrator
  ```

  Without a description, the storyteller engine uses a plain one based on the
  voice (for example "an adult American woman").

### Writing good character descriptions (2026-10-26)

Qwen3-TTS accepts any length and its documentation gives no guidance, so this is
how these models generally behave, not a measured limit:

| | Length | What it gets you |
|---|---|---|
| Minimum | ~5–8 words | Gender, age, accent and one quality: *"A calm, middle-aged British man."* Less than that and the model guesses; the voice wanders more. |
| **Sweet spot** | 1–2 sentences, ~15–40 words | Who (gender, age, accent), how the voice sounds (low, gravelly, bright, breathy), and their manner (unhurried, clipped, warm). |
| Too long | past ~60 words | Nothing breaks, but extra words add less and less: the model latches onto a few traits and the rest dilutes. Contradictory traits make the voice wobble. |

- **Describe the sound, not the biography.** "Low, precise, unhurried" changes the
  voice; "lost her lab to a scandal" doesn't. The model can't hear backstory.
- **Emotions go on the line, not in the description** (`Boombs (furious): …`). The
  description applies to every line, so "furious" there makes them furious all the
  time. A standing trait ("always weary") does belong in the description.
- **The description does two jobs.** With voice matching it designs the character's
  reference voice *and* guides each line's acting, so timbre words (pitch, texture,
  accent) count most.

## 2. The voices

Use the name or the id. The first eight are the ones you picked.

| Name | Id | Accent | |
|---|---|---|---|
| **Heart** | af_heart | US | female |
| **Bella** | af_bella | US | female |
| **Nicole** | af_nicole | US | female |
| **Michael** | am_michael | US | male |
| **Fenrir** | am_fenrir | US | male |
| **Emma** | bf_emma | UK | female |
| **George** | bm_george | UK | male |
| **Fable** | bm_fable | UK | male |
| Aoede | af_aoede | US | female |
| Kore | af_kore | US | female |
| Sarah | af_sarah | US | female |
| Nova | af_nova | US | female |
| Alloy | af_alloy | US | female |
| Sky | af_sky | US | female |
| Jessica | af_jessica | US | female |
| River | af_river | US | female |
| Puck | am_puck | US | male |
| Echo | am_echo | US | male |
| Eric | am_eric | US | male |
| Liam | am_liam | US | male |
| Onyx | am_onyx | US | male |
| Adam | am_adam | US | male |
| Isabella | bf_isabella | UK | female |
| Alice | bf_alice | UK | female |
| Lily | bf_lily | UK | female |
| Lewis | bm_lewis | UK | male |
| Daniel | bm_daniel | UK | male |

Tip: hear any of them in the app under the voice icon (▶ next to each name).

## 3. Lines

After the cast list, **every line is spoken on its own**.

| You write | What happens |
|---|---|
| `Tom: Everything's green.` | Tom's voice |
| `Tom (whispering): Don't tell anyone.` | Tom, with a delivery |
| `Tom: (whispering) Don't tell anyone.` | Same — script-style parenthetical |
| `[Tom, whispering] Don't tell anyone.` | Same — bracket style |
| `[slowly] A deployment finished.` | Narrator, with a delivery |
| `[pause 2s]` or `[pause 500ms]` | Silence (up to 30 s) |
| `Any other line.` | Narrator |
| `Note: this is fine.` | Narrator — `Name:` only counts for names in the cast list |

## 4. Delivery words

Write deliveries in plain words; several can be combined (`flat, furious, quiet`).

**Today (Kokoro voices on your phone) a delivery can only change speed and loudness.**
Kokoro can't really whisper, shout or act, so this is an approximation:

| Words | Effect today |
|---|---|
| whisper, whispering, hushed, murmur, under her/his breath | much quieter, a little slower |
| quiet, quietly, soft, softly, low, gently | quieter, a little slower |
| shout, shouting, yell, scream, loud, full voice | much louder, a little faster |
| angry, furious, firm, commanding | louder |
| excited, urgent, fast, quickly, breathless, panicked | faster, a little louder |
| sad, somber, tired, slow, slowly, flat, grave, solemn | slower, a little quieter |
| calm, measured, dry, deadpan | very slightly slower |

Any other words (`not looking up`, `amused`, `like a nature documentary`) are
kept but have no effect yet.

**With the storyteller renderer** ([`render/`](../render/README.md), on a PC with an
NVIDIA card), the same delivery words become real acting instructions: whispering
that sounds like whispering, a rising question, a narrator who sounds amused.
Same files, nothing to change. Cast documents are acted by Qwen3-TTS, from the
character's description plus the delivery words.

## 5. Punctuation

- `?` and `!` reach the voice model. Kokoro lifts questions only slightly.
- Lines ending in `!` are made a little louder automatically.
- Commas, colons and full stops get natural pauses; tune them in the app
  under **Pauses** (Short / Natural / Long).

## 6. Good to know

- Each line can hold several sentences; they all use that line's voice.
- Blank lines are ignored inside a cast document.
- Mixing US and UK voices is fine; both are kept loaded.
- Markdown symbols like `**bold**` are stripped before speaking.
