---

# mtt_ShufflePlayer.lua — where we left off

updated: 2026-11-20

- Done:
  - Documented Stop and Play using the last completed render, and Render & Start for explicit replacement.
  - Lua syntax and ReaScript API checks passed. A Lua test with mocked REAPER calls covered Stop/Play without a new render, timeout preserving the previous batch, successful replacement, and exit cleanup.
- Not done:
- Waiting on:
  - Update the REAPER action to point to `ShufflePlayer/mtt_ShufflePlayer.lua`. Collapse and reopen the window to check that the FmodSync styling remains intact and no style-stack error occurs.
  - In REAPER, render two items, press Stop, change the selection, and press Play. Confirm that the original two items play without a new render. Then use Render & Start to replace them with the new selection.
  - Confirm in REAPER that a render timeout leaves the previous batch playable and that closing the script removes the player and its tracked temporary files.
