---

# mtt_MemoryEstimate.lua

<!-- state: mtt_MemoryEstimate.state.md · wanted: mtt_MemoryEstimate.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

Estimates the memory footprint of empty items (items with no PCM source) on top-level
tracks in a REAPER project. For each such item, it computes the theoretical rendered
file size using the item's length, the track's channel count, and the user-selected
output format (PCM 16/24/32-bit, FADPCM, or Vorbis). When Vorbis mode is enabled and
a pre-rendered file exists in the project's Render folder, the script can perform
spectral analysis on that file to derive a content-aware quality factor, producing a
more accurate estimate for variable-bitrate audio. Results are grouped by category
patterns (Point_, Zone_, Int_, etc.) and displayed as a stacked bar with a detachable
details table.

## Ruled out

