# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - RGB cycling border on the hovered favorite button: while hovered, `render_favorite_button` pushes an extra `ImGui_Col_Border` whose RGB channels are three sine waves phase-shifted 120°, driven by `reaper.ImGui_GetTime`; the pop count is a variable (`n_pushed_col`) so the cycling border is popped only when pushed. Once the mouse leaves, the border falls back to the per-type color (blue-grey action / dark-green fx). The knobs are the `FAV_*` constants next to the other layout ones: `FAV_HOVER_HUE_PERIOD` (seconds per full cycle, 2.0), `FAV_HOVER_BORDER_BASE` (1) and `FAV_HOVER_BORDER_EXTRA` (2, so hover = 3px).
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button and check the border cycles through the RGB hues smoothly (no flicker), then move the mouse away and check the border returns to the normal per-type color.
  - In-REAPER run: with favorites of very different name lengths, check the gaps between buttons are equal across rows and every row's first button starts at the same x.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - In-REAPER run, docked shelf: hover a favorite button (font +10%, +4px, 3px border, subtle fill, centered in its slot) and check the buttons to the right don't move, rows don't jump, and no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
