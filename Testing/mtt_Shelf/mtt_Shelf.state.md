# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - The drag "negative" ghost (standard-size source button with a light-gray silhouette, hover ring/font/size and pressed feedback suppressed, palette ring only on the preview) is committed; the code comments corrected to match the gray the user tuned in REAPER (`FAV_DRAG_SRC_GRAY` 0.05 → 0.3, a brighter silhouette than the window background).
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button, then move the mouse away: the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
