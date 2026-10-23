# mtt_Shelf — where we left off

updated: 2026-10-22
- Done:
  - Top flush: pushed `WindowPadding` to (x, 0) before `ImGui_Begin` of the main "Shelf" window (content rect is computed there) and popped it after the visible block — zeroes the theme's top/bottom margin, keeps the horizontal one.
  - `draw_action_fx_buttons`: Action/Fx/Preset are "text-only" (transparent `Col_Button`/`Hovered`/`Active` + `FrameBorderSize` 0). `draw_upper_text_button` gives them a hover cue: theme text is already white, so the label rests at 0.7 gray and goes full white under the cursor (two-frame idiom via `hovered_upper_btn`/`current_upper_btn`, synced by `reset_upper_hover()`). The "Add:" label now rests at the same 0.7 gray. Favorite buttons untouched.
  - `FrameRounding` in `apply_style` is 2 (subtle rounding on frame widgets); hover palette ring reads the same var.
- Not done:
- Waiting on:
  - User to test: the first separator sits at the top border (docked mode still has a ~1px Dummy + item-spacing below it); bottom margin is now gone too.
