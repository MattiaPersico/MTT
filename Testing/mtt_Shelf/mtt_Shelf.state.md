# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - Drag preview (wanted #4) was still broken after the first attempt: the user saw a bare label plus a small empty square, no button. The square and the text were ReaImGui's built-in preview tooltip, which `BeginDragDropSource` opens by default — now suppressed with `ImGui_DragDropFlags_SourceNoPreviewTooltip`. The button was invisible because the theme's `FrameBorderSize` is 0, so no frame is drawn; `FrameBorderSize 1` is now pushed around the source `Button` in `render_favorite_button` and in `render_fx_drag_preview`, so the preview copy always shows the same frame as the source in any theme.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run of the preview look: while dragging, only the button copy (name + green border, subtle hover fill) locked at the grab point — no floating text, no square. Confirmed → remove wanted #4.
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
