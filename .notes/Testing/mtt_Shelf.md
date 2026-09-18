# mtt_Shelf.lua

<!-- Format: .notes/_TEMPLATE.md · "Where we left off" is replaced in full, never appended
     to · "Wanted" is the user's: delete an entry when you implement it, never write one ·
     if this note and the code disagree, the code is right and the note is fixed now. -->

## What it is

A per-project shelf of the actions and effects the user reaches for most: a small window of buttons where a click runs an action and a drag drops an FX onto the track under the cursor, so the frequent operations of the current session are one click away instead of a trip through the action list or the FX chain picker. Each project keeps its own favorites,so the shelf is tailored to the work it sits next to.

## Ruled out

- 2026-09-17 — the saved format filters "were never applied on load": NOT the parse pattern. `^(%S+)|([01])$` on "VST|1" captures "VST" and "1" — in Lua patterns | is a plain character, not a metapattern (the metacharacters are ^ $ ( ) . % [ ] * + - ?), identically in 5.4 and 5.5. Excluded twice: verified by running in plain lua and in REAPER's Lua. The rewrite to `^(%S+)%.([01])$` was unnecessary and made every already-saved pipe-separated filter file unreadable; it is reverted.

## Where we left off

updated: 2026-09-18 · HEAD 08488c2 · tree: modified: Testing/mtt_Shelf.lua, .notes/Testing/mtt_Shelf.md

- Done: the FX popup keeps its filter bar (case-insensitive substring match, "Nessun FX trovato" when nothing matches), keyboard focus on open, the capped list in a fixed-height child, and the popup width limited to the longest shown name via SetNextWindowSize on appearance (unconfirmed in REAPER).
- Done: the filter is now five checkboxes (VST, VST3, AU, JS, CLAP) on the filter input's row. The 'i' checkboxes are gone: fx_visible strips a trailing "i" from the name prefix before the lookup, so "VSTi: ", "VST3i: ", "AUi: " and "CLAPi: " rows follow the base format's checkbox (unchecking VST removes both "VST: " and "VSTi: " rows — in the list and in the width calculation, which both call fx_visible); unknown prefixes are never filtered, and the strip is case-sensitive so a prefix like "MIDI" is left alone. All five checkboxes share the input's row: the SameLine moved inside the loop, and the input got SetNextItemWidth(ctx, 100) before it, because its default width (~65% of the window) is what pushed everything after it to the next row.
- Done: load_format_filters keeps the original pattern `^(%S+)|([01])$` — the "parse was broken" explanation is ruled out (see Ruled out); the rewrite to `^(%S+)%.([01])$` was reverted because it made every already-saved pipe-separated filter file unreadable. save_format_filters is unchanged and still writes one "name|flag" line per format with |. Old seven-line files read fine, the AUi/VST3i lines are ignored by the guard; the saved file (.mtt_shelf_format_filters.txt, global) holds five lines.
- Done: LoadAllFX's dedup (priority map, prefix stripping) stays on the original four formats, so a plugin enumerated in two formats shows as two rows and the checkbox hides the extra one; the in-REAPER file I/O is still untested.
- Not done: the trailing-"i" strip in fx_visible was not run — the terminal tool failed every attempt in that session ("tool input was not fully received"), so the cases were reasoned through instead: all nine prefixes, unknown prefixes, no-prefix names, an old seven-line file. The filter-pattern round-trip it also listed as untested has since been run in plain lua (5.5) and in REAPER's Lua (5.4): see Ruled out.
- Done (2026-09-18): selecting an FX now closes the popup itself. After the favorite is inserted into favorites and saved (main_loop, ~L607) a reaper.ImGui_CloseCurrentPopup(ctx) runs — the same call the "Annulla" menu item already uses (~L620) — so the search/selection window that added the FX closes the moment the favorite is stored, instead of staying open waiting for Annulla.
- Waiting on: a run in REAPER to confirm the popup closes right after picking an FX (the case most likely to break: pick an FX and expect the window to dismiss on its own, not only after clicking Annulla), plus the still-unconfirmed items from before (one-row layout, 100px input width, toggling a format hides/restores both rows, five-line filter file persists and re-applies on reload, CLAP/VSTi/CLAPi/VST3i rows filter, focus, capped list, width limit) — and a commit: the work exists only in the working tree.

## Wanted

1. The appendix text from the buttons should be removed (like Script: or VST3: ecc)
2. remove Fx duplicates. If a plugin is available in multiple formats, only one row should be shown (priority is: CLAP, VST3, AU, VST, JS)
