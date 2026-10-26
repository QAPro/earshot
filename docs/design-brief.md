# Earshot design brief

*Locked 2026-10-26 with Phil via the design-partner skill. Canvas of the three directions:
private claude.ai artifact "Earshot redesign directions". Tokens are in `lib/ui/theme.dart`
(the source of truth). This file says why.*

## Foundation

- **Product:** offline read-aloud for documents, Android (Galaxy S25) and Windows 11.
- **Use:** listening while hands and eyes are on other, low-attention work (manual testing).
- **The one design rule:** readable at a glance from arm's length; controls big enough to hit
  without looking closely; playback reachable from anywhere.
- **Personality:** calm, confident, a little warm. **Not:** fiddly, dense, "settings app".

## Direction: B "Now Playing", with grafts

Chosen over A (Reading Room: book-like, calm, small controls) and C (Instrument: precise,
labelled, document map, busy).

- **Player** is the centre: the sentence being read at 20–30 pt bold (size follows length), the
  sentences either side faded, a 92 pt amber play button, previous/next sentence and paragraph.
- **Library** keeps a docked "now playing" bar so playback is one tap away.
- **From A:** the read-along view in Literata, current sentence marked like a highlighter.
- **From C:** paragraph marks on the progress bar (tap/drag to jump).
- **Windows (≥900 px):** player on the left (440 px), read-along text on the right, line length
  capped at 640 px. Library capped at 720 px.

## Tokens (see `lib/ui/theme.dart`)

| Token | Dark | Light | Role |
|---|---|---|---|
| bg | `#0E1014` | `#F7F7F5` | page |
| surface / surface2 | `#181B21` / `#22262E` | `#FFFFFF` / `#ECEDEF` | cards, sheets / controls on them |
| text / muted / dim | `#F2F3F5` / `#9AA1AD` / `#7D8492` | `#14161A` / `#5B6270` / `#6B7280` | all ≥4.5:1 on bg |
| accent | `#F5B544` | `#F2A93B` | play button fill, selection: a **fill**, never thin text on light |
| accentStrong | `#F5B544` | `#9A6200` | progress fill, links, speaker names: passes contrast on light |

- **Light/dark:** follows the phone/PC setting.
- **Type:** Manrope (UI, variable, bundled) and Literata (reading view, variable, bundled). Both
  SIL OFL, in `assets/fonts/`. Bundled because the app is offline.

## Do / Don't

**Do:** big round controls (≥44 pt, main ones 56–92); one amber thing per screen that matters
most; time left everywhere; labels in plain words ("Keep going", "Prev doc").

**Don't:** icon-only controls without a tooltip/semantic label; amber text on light backgrounds
(use accentStrong); a round button on a surface of the same colour (use `onSurface`; it was
invisible once).

## Reviewing changes

Render the real screens in both themes without a phone:

```bash
flutter test test_screens --update-goldens   # PNGs in test_screens/out/
```
