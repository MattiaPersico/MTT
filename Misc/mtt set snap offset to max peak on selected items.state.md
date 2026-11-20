# mtt set snap offset to max peak on selected items — where we left off

updated: 2026-11-20
- Done: Added the SWS dependency check and skipped missing or MIDI takes, unusable item lengths and invalid peak positions. Syntax and Lua stub tests passed for an empty selection, missing SWS, mixed items and peak boundaries.
- Not done: No known implementation item outstanding.
- Waiting on: REAPER/SWS check with a trimmed, rate-shifted audio item, silence and mixed selections; real peak positions and scan time were not measured.
