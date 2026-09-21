# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - Hover "raised" feel completed: while a favorite button is hovered (previous frame, same 1-frame-lag sync as the border) it also renders with the font at 110% (`ImGui_PushFont(ctx, nil, GetFontSize * 1.1)`, popped after the button) and +4px height; its width is measured with the bigger font so the label grows with it. `render_favorites_flow` reserves the same ~10% extra width in the wrap math so the hovered button never overlaps its neighbor.
  - Docked window styling (earlier): sharp corners, 1px window border, frame-only favorite buttons (colored border, transparent interior), reduced height; hover border 1px -> 3px; hover interior fill alpha 0.2; tooltip popup removed.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run, docked shelf: hover a favorite button (border 3px, font + size slightly bigger, subtle fill), move to a neighbor (old button must reset to 1px/standard size), and check no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
