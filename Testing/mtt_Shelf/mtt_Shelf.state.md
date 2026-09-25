# mtt_Shelf — where we left off

updated: 2026-09-25
- Done:
  - Custom left scrollbar in both docked and undocked modes (option 1): undocked — main window sets `WindowFlags_NoScrollbar` (native right bar hidden, wheel still scrolls) and all content is shifted right by `LEFT_SB_W + LEFT_SB_GAP`; docked — the `##shelf` child uses `NoScrollbar | HorizontalScrollbar` (native vertical bar hidden, wheel still scrolls; the horizontal one is a fallback for a single favorite wider than the dock), `sb_top_x/y`/`sb_avail_h` are taken each frame from the child's content region, favorites are shifted by `LEFT_SB_W + LEFT_SB_GAP` and `draw_left_scrollbar` draws track + grab on the child's scroll state at the end of the frame. The `+Action/+Fx/+Preset` row is shifted the same amount in docked mode so it aligns with the first favorites row. `render_favorites_flow` takes an optional `extra_limit` and wraps rows on the remaining `GetContentRegionAvail` width, so the right edge never leaves the content region.
- Not done:
  - Hand cursor over draggable FX (wanted 2): deferred by the user, to be done later.
- Waiting on:
  - User check, docked shelf with enough favorites to overflow the dock height: the left track + grab appears, wheel scroll, grab drag, track click work; the +Action row aligns with the first favorites row; no horizontal bar in normal use.
  - User check, undocked (content taller than the window): wheel scroll, grab drag, track click; the left strip never covers the first favorite button.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
