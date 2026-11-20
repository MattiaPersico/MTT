---

# mtt_ShufflePlayer.lua

<!-- state: mtt_ShufflePlayer.state.md · wanted: mtt_ShufflePlayer.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

SFX Preview plays shuffled previews of selected media items at a configurable rate (30–4000 ms). Render & Start renders the current selection and starts playback. Stop halts playback without discarding the last completed render; Play reuses it without rendering again, even if the selection has changed. A render timeout leaves the previous batch available until the script closes.

## Ruled out
