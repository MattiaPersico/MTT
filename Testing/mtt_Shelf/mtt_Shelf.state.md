# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - Press feedback on favorite buttons (wanted #1, confirmed working in REAPER): while a button is held down it shrinks by `FAV_PRESSED_SHRINK_X/Y` (4x2px), stays centered in its slot so the layout never moves and the neighbors don't shift, gets a visible fill and a brighter border in the type color, and its font returns to base size (inverse of the hover 1.1x "lift"). The pressed button is tracked with `IsItemActive` right after the `Button` (last-item-safe spot) into `current_pressed_idx`, synced frame-end by `reset_pressed_if_none()` at both call sites of `reset_hovered_if_none()` (docked child and undocked path).
- Not done:
  - Invisible drag preview window + grab-point tracking (wanted #4): designed, not written. Full design:
    - New module locals `drag_grab_x`, `drag_grab_y` next to `isDraggingFx`/`draggedFx`.
    - In `render_favorite_button`, the `BeginDragDropSource` block keeps only `isDraggingFx = true; draggedFx = fav` + `EndDragDropSource`; the 4 pushed colors and the preview `Button` move out of it. On the same frame capture the grab point: `mx, my = reaper.ImGui_GetMousePos(ctx)`, then `drag_grab_x = mx - rect_min_x`, `drag_grab_y = my - rect_min_y` (`rect_min` is already captured a few lines above; `GetMousePos` and `GetItemRectMin` share the same screen space as `SetNextWindowPos`).
    - New `render_fx_drag_preview()` (define before `main_loop`): display name via `favorite_display_name(draggedFx)`; button width = `CalcTextSize(name) + FAV_BTN_PAD_X`, height = `FAV_BTN_H`; `SetNextWindowPos(mouse - grab, Cond_Always)`, `SetNextWindowBgAlpha(0)`, push `StyleVar_WindowBorderSize 0` and `StyleVar_WindowPadding 0,0` plus the same 4 FX colors the source block used (Border 0.3,0.5,0.35,1 / Button a0 / Hovered a0.2 / Active a0); `Begin("##ShelfDragPreview", true, NoDecoration|NoBackground|NoMove|NoSavedSettings|AlwaysAutoResize)`; one `Button("##shelf_drag_preview", btn_w, FAV_BTN_H)` with no handler; `End` inside the `if`; pop 2 style vars + 4 colors.
    - Call it in `main_loop` after the shelf's `ImGui_End`, still inside `if visible`, before `pop_style()`, guarded by `if isDraggingFx`.
    - Drop handling (`IsMouseReleased` + `BR_GetMouseCursorContext`) stays untouched.
    - Open risk: with the source block now empty, the built-in drag preview may still show a zero-size dot (window bg/border) following the cursor; if so, push `Col_WindowBg`/`Col_WindowBorder` alpha 0 while the drag is active.
- Waiting on:
  - Implement wanted #4 (design above), then in-REAPER run: drag an FX favorite — the preview must be an invisible window containing only the button, the button must follow the cursor exactly at the press point, the drop on a track must still work, and no residual dot from the built-in preview.
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
