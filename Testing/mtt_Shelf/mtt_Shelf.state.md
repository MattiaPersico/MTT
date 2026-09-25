# mtt_Shelf — where we left off

updated: 2026-09-25
- Done:
  - The window background now follows the active REAPER theme at runtime: `col_main_bg` is read once at startup with `reaper.GetThemeColor("col_main_bg")` (top of the file), the signed AARRGGBB is unpacked into `theme_bg_r/g/b`, and `apply_style` pushes it as `WindowBg` (opaque). Fallback is the old `#282828` when the read returns -1. The hardcoded `#282828` matched the user's reference image, confirming the key; only the alpha byte is discarded (painted opaque).
- Not done:
  - None.
- Waiting on:
  - User check in REAPER that the background still matches their reference (it should, since the value equals `#282828` for their theme), and ideally with a second theme to see it adapt.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
