# mtt_QuickLoopPreview

<!-- state: mtt_QuickLoopPreview.state.md · wanted: mtt_QuickLoopPreview.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

A toggle for auditioning the current item selection as a continuous loop. On, it bounces the master mix of the selected range to a cached WAV — muting only the unselected items that overlap it, and reusing the last bounce when the selection, its tracks, the master and the span are all unchanged — then inserts a temporary additive player on the master channel and loops it. Off, it removes the player and restores the master's channel count, leaving the cache on disk for the next on. Requires REAPER 6.44+; no SWS.

## Ruled out
