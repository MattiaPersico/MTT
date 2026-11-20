# mtt transport play loop — where we left off

updated: 2026-11-20
- Done: Fixed the time-selection query and guarded the existing preparation action without adding a fallback. Removed the inactive local scan and preserved latch reset, loop-point copy, Repeat and Play order. Saved-file Lua verification found no signature errors (5 arguments not checked); 3 transport mock cases passed. Action IDs were checked against their documentation cards.
- Not done:
- Waiting on: REAPER confirmation of the preparation action registration and playback with an empty time selection or an already-playing transport.
