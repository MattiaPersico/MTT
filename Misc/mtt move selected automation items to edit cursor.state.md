# mtt move selected automation items to edit cursor — where we left off

updated: 2026-11-20
- Done: Preserved the first-index anchor and resolved indices again before each directional move. Saved-file Lua verification found no signature errors (12 arguments not checked); 14 mock cases passed, including reordering, crossing and coincident items.
- Not done:
- Waiting on: REAPER confirmation of actual index reordering and position handling, especially for negative targets.
