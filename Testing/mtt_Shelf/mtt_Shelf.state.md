# mtt_Shelf — where we left off

updated: 2026-09-27
- Done:
  - Hand cursor on the draggable FX favorites: Dear ImGui exposes no open/closed hand (only the pointing one, like its hyperlinks), so `ImGui_MouseCursor_Hand` on hover of an FX favorite and during the FX drag, `Arrow` otherwise — `SetMouseCursor` is per-frame, and the hover is read from `hovered_favorite_idx` (not `current_hovered_idx`, which is reset to -1 at the top of the frame). User confirmed: "perfetto".
  - Drop on the shelf is a no-op: the guard is a rect hit test (mouse screen coords vs `GetWindowPos`/`GetWindowSize`), same pattern as `draw_left_scrollbar` — `IsWindowHovered` rejects the `AllowWhenOverlapped*` family (an IsItemHovered flag) with "Invalid flags for IsWindowHovered()!", and a falsy guard let the insert through to the selected tracks.
- Not done:
- Waiting on:
