# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - The drag grab point is now captured on the mouse-down frame (`drag_grab_x/y` recorded from `GetMousePos` at first press inside `render_favorite_button`, cleared on mouse release in `main_loop`) instead of at `BeginDragDropSource` activation, so a fast flick no longer bakes a 10–20px slip into the grab reference; the old mouse-current capture is kept only as a fallback (it should not fire).
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button, then move the mouse away: the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
  - In-REAPER run: drag an FX favorite out with a fast flick — the floating preview appears with the cursor on the point where the press happened (no initial slip); the 30fps trailing at high speed remains by design.
