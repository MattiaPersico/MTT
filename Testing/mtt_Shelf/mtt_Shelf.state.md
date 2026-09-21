# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - Hover enlargement now centered via a fixed slot: every favorite occupies a slot of the hover dimensions (font × `FAV_HOVER_FONT`, height `FAV_BTN_H + FAV_HOVER_H`), the un-hovered button is drawn centered inside it (`SetCursorPos` offset), so the hovered button grows in place, the buttons to the right never shift, and the rows never reflow (the wrap math always uses the hover width). The flow no longer uses `SameLine`: the row origin is captured with `GetCursorPos`, each wrap advances the row by `slot_h + ItemSpacing.y` (read via `ImGui_GetStyleVar`), and a final `SetCursorPos` pins the content max so scrollbars and undocked auto-height don't depend on which button is hovered. `render_favorite_button(i, btn_w, btn_h)` now receives its size from the flow instead of measuring it.
  - The final slot-bottom `SetCursorPos` pin now has a zero-size `ImGui_Dummy` after it: the pin leaves the cursor past the registered content max (slot padding below/right of the last button) with no item submitted, and `ImGui_End`/`EndChild` raised the "Code uses SetCursorPos()/SetCursorScreenPos() to extend window/parent boundaries" user-assertion. The dummy registers the extended position without drawing or taking clicks.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - In-REAPER run, docked shelf: hover a favorite button (font +10%, +4px, 3px border, subtle fill, centered in its slot) and check the buttons to the right don't move, rows don't jump, and no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
