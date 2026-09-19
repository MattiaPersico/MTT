---

# mtt_ShufflePlayer.lua

<!-- state: mtt_ShufflePlayer.state.md · wanted: mtt_ShufflePlayer.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

SFX Preview — renders selected media items to temporary audio files one at a time, generates a JSFX on the fly that loads all rendered files into memory, and plays them back in a shuffled random loop with a configurable rate (40–4000 ms). It provides a ReaImGui window with a rate slider, status text, and Render & Start / Stop & Clear buttons, while properly saving and restoring all render settings and cleaning up all resources on exit.

## Ruled out
