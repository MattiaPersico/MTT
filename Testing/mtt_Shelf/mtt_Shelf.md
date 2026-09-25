# mtt_Shelf

<!-- state: mtt_Shelf.state.md · wanted: mtt_Shelf.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

A per-project shelf of the actions and effects the user reaches for most: a small window of buttons where a click runs an action and a drag drops an FX onto the track under the cursor, so the frequent operations of the current session are one click away instead of a trip through the action list or the FX chain picker. Each project keeps its own favorites, so the shelf is tailored to the work it sits next to.

## Ruled out

- Always call this mtt_Shelf not scaffale.
- 2026-09-17 — the saved format filters "were never applied on load": NOT the parse pattern. `^(%S+)|([01])$` on "VST|1" captures "VST" and "1" — in Lua patterns | is a plain character, not a metapattern (the metacharacters are ^ $ ( ) . % [ ] * + - ?), identically in 5.4 and 5.5. Excluded twice: verified by running in plain lua and in REAPER's Lua. The rewrite to `^(%S+)%.([01])$` was unnecessary and made every already-saved pipe-separated filter file unreadable; it is reverted.
- 2026-09-20 — the shelf auto-closing when a favorite action does not work, crashes or is no longer at its path: NOT guaranteed; there is no current solution. The shelf's lifetime after a failed action is undefined: do not design on the assumption that it closes, or that it survives.
- 2026-09-25 — moving the undocked window scrollbar to the left: NOT a window flag. The ReaImGui docs have no flag that moves the native vertical scrollbar to the left (only NoScrollbar / AlwaysVerticalScrollbar / AlwaysHorizontalScrollbar / HorizontalScrollbar); a custom-drawn bar on the same scroll state is required (draw_left_scrollbar).
