# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - Drag preview button shows the rotating palette ring: native border made transparent, `draw_palette_ring` drawn around the preview button rect (same thickness, rounding and time phase as the source hover ring). The source button hover keeps its ring — the user chose "add it on the preview" over "move it".
  - Fixed a crash when the drag starts: the preview block closed the window with `reaper.ImGui.End(ctx)` (there is no `ImGui` field on `reaper`); restored `reaper.ImGui_End(ctx)`, the call the pre-ring code used.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: drag an FX favorite: no crash on drag start, the preview follows the cursor with the ring rotating around the button (no visible seam where the lap closes, no flicker), the drop still works, and the source button hover is unchanged.
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
