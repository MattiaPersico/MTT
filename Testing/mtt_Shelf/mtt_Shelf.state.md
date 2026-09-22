# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - Added a trailing comment next to the five layout constants (`FAV_BTN_H`, `FAV_BTN_PAD_X`, `ITEM_SP_X`, `FAV_HOVER_FONT`, `FAV_HOVER_H`), so each is self-describing.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run: with favorites of very different name lengths, check the gaps between buttons are equal across rows and every row's first button starts at the same x.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - In-REAPER run, docked shelf: hover a favorite button (font +10%, +4px, 2px palette ring, subtle fill, centered in its slot) and check the buttons to the right don't move, rows don't jump, and no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
