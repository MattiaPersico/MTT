# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - Constant slot inset in the favorites flow: the unhovered button was centered inside a slot sized to its own hover footprint (1.1x font), so the inset — and therefore both the gap between buttons and the left edge of each row — varied with name length. `render_favorites_flow` now does a first pass computing `max_extra` (the largest hover width growth across all favorites) and sizes every slot as `btn_w + max_extra`: the centering inset is identical for all buttons, so inter-button gaps, row left edges and row wrapping are uniform. The hovered button still fills its slot and grows in place; for the longest name the slot coincides with its hover size, shorter ones get a bit of extra breathing room.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: with favorites of very different name lengths (e.g. "RBass" next to "mtt_QuickLoopPreview" and "Custom Transport - Play/Stop"), check the gaps between buttons are equal across rows and every row's first button starts at the same x.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - In-REAPER run, docked shelf: hover a favorite button (font +10%, +4px, 3px border, subtle fill, centered in its slot) and check the buttons to the right don't move, rows don't jump, and no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
