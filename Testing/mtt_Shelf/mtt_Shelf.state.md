# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - The drag grab point is now captured on the mouse-down frame (`drag_grab_x/y` recorded from `GetMousePos` at first press inside `render_favorite_button`, cleared on mouse release in `main_loop`) instead of at `BeginDragDropSource` activation, so a fast flick no longer bakes a 10–20px slip into the grab reference; the old mouse-current capture is kept only as a fallback (it should not fire).
- Not done:
  - None.
- Waiting on:
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
