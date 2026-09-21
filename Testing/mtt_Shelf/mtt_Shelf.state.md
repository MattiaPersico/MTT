# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - Hover border is now a chromatic ring that rotates around the button instead of the whole outline cycling at once: while hovered the native `Col_Border` is pushed transparent (a single style color cannot vary around the perimeter) and `draw_hue_ring` draws the ring on the window draw list — the button rect (from `ImGui_GetItemRectMin/Max`) inset by half the ring width, its rounded-rect perimeter split into ~6px segments (4 per corner arc), each segment colored with the same three-sine hue formula phase-shifted by its position along the perimeter, so the hues go around the button (one full hue cycle per lap) while `reaper.ImGui_GetTime` / `FAV_HOVER_HUE_PERIOD` (1.0) spins the wheel. Ring thickness = `FAV_HOVER_BORDER_BASE + FAV_HOVER_BORDER_EXTRA` = 2px; the old hover `FrameBorderSize` push/pop went away with the visible border it sized. Geometry tested in plain Lua (wide, narrow and near-square rects: chain closed, inside the rect, seam colors match, hues rotate); `math.hypot` avoided in favor of `sqrt` (removed in Lua 5.5, present in REAPER's 5.4 — the helper must run on both).
- Not done:
  - None.
- Waiting on:
  - In-REAPER run: hover a favorite button and check the ring shows the hues rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run: with favorites of very different name lengths, check the gaps between buttons are equal across rows and every row's first button starts at the same x.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - In-REAPER run, docked shelf: hover a favorite button (font +10%, +4px, 2px chromatic ring, subtle fill, centered in its slot) and check the buttons to the right don't move, rows don't jump, and no `Missing Pop*` console errors.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
