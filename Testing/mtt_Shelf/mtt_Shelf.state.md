# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - User confirmed the drag preview reads as a copy of the source favorite button (name + green frame, locked at the grab point); removed wanted #4.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
