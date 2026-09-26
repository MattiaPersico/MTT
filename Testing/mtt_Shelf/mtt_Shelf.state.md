# mtt_Shelf — where we left off

updated: 2026-09-26
- Done:
  - Custom left scrollbar visual (`draw_left_scrollbar`): track + grab rects now offset by `GetWindowPos` (DrawList works in screen coordinates) — user tested: still never visible, so the origin/coordinate convention is suspect. Added a temporary debug block at the top of the function with three 20×20 markers (green = `GetCursorScreenPos` at the strip origin, blue = `GetWindowPos` origin, red = green + 100px, i.e. guaranteed inside the content) to pin down where the window DrawList actually draws.
- Not done:
  - Custom left scrollbar visual: markers in place, awaiting the user's REAPER run (docked vs undocked) to identify the real coordinate behavior before choosing the fix.
  - Hand cursor over draggable FX (wanted 2): deferred by the user, to be done later.
- Waiting on:
  - User check: shelf with overflowing content (wheel scrolls) — which of the three colored squares (green/blue/red) are visible and where, docked and undocked.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
