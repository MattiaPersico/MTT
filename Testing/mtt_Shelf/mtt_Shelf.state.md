# mtt_Shelf — where we left off

updated: 2026-10-13
- Done:
  - Left scrollbar always visible: `draw_left_scrollbar` no longer returns early when the content fits (`max_y <= 0`); the grab then fills the whole track and the drag is disabled in that state.
- Not done:
- Waiting on:
