# mtt_Shelf — where we left off

updated: 2026-09-24
- Done:
  - Repositioned the drag preview (`render_fx_drag_preview`) below the mouse with a fixed offset (`DRAG_PREVIEW_OFFSET_Y = 20`), same scheme as mtt_envelope_stealer: the pointer stays outside the window, REAPER keeps receiving the moves and the release, the arrange's internal cursor position (what `BR_*AtMouseCursor` reports) stays fresh, so the drop resolves. The user confirmed the drop now works on a normal drag.
  - Removed `ImGui_WindowFlags_NoMouseInputs` (user tested: with the window centered under the cursor it did not fix routing) and the now-unused grab-point capture (`drag_grab_x/y`, `drag_grab_captured`).
  - The drop still resolves the target position-based via `BR_TakeAtMouseCursor`/`BR_TrackAtMouseCursor` (+ `ValidatePtr`, arrange-only gate `context == 2`), take before track, `*FX_AddByName` + `SetOpen`.
  - Clicking an FX button now inserts that FX into selected items (takes) if any items are selected, otherwise into selected tracks: `insert_fx(fav.ident)` called from the click handler at line 837, reusing the same `TakeFX_AddByName`/`TrackFX_AddByName` + `SetOpen` pattern.
- Not done:
  - None.
- Waiting on:
  - A short wiggle that never leaves the shelf should drop nothing (the arrange's internal position is "if applicable"): not yet confirmed by the user.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
