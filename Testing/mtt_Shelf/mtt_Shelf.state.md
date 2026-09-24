# mtt_Shelf — where we left off

updated: 2026-09-25
- Done:
  - The shelf window background is fully transparent (wanted 2): `ImGui_SetNextWindowBgAlpha(0)` before `Begin` in `main_loop` (the same helper the drag preview already used), before the docked child `BeginChild`, and the scrollbar background in `apply_style` dropped to alpha 0. REAPER's own background (docked panel or arrange) shows through, so the shelf camouflages in any theme instead of painting a fixed dark gray; the 1px window border remains as the outline. Buttons and popups are unchanged.
- Not done:
  - None.
- Waiting on:
  - User check that the camouflaged background reads right on their setup, both docked and floating.
  - A short wiggle that never leaves the shelf should drop nothing (the arrange's internal position is "if applicable"): not yet confirmed by the user.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
