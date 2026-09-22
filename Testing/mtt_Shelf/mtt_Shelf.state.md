# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - User confirmed the drag preview now shows the enlarged (hover) button dimensions: width = slot width (base text + shared 1.1x extra from `render_favorites_flow`), height = slot height, name at `fs * 1.1`.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
