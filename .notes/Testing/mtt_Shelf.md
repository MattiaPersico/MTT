# mtt_Shelf.lua

<!-- Format: .notes/_TEMPLATE.md · "Where we left off" is replaced in full, never appended
     to · "Wanted" is the user's: delete an entry when you implement it, never write one ·
     if this note and the code disagree, the code is right and the note is fixed now. -->

## What it is

A per-project shelf of the actions and effects the user reaches for most: a small window of buttons where a click runs an action and a drag drops an FX onto the track under the cursor, so the frequent operations of the current session are one click away instead of a trip through the action list or the FX chain picker. Each project keeps its own favorites,so the shelf is tailored to the work it sits next to.

## Ruled out

- 2026-09-17 — the saved format filters "were never applied on load": NOT the parse pattern. `^(%S+)|([01])$` on "VST|1" captures "VST" and "1" — in Lua patterns | is a plain character, not a metapattern (the metacharacters are ^ $ ( ) . % [ ] * + - ?), identically in 5.4 and 5.5. Excluded twice: verified by running in plain lua and in REAPER's Lua. The rewrite to `^(%S+)%.([01])$` was unnecessary and made every already-saved pipe-separated filter file unreadable; it is reverted.

## Where we left off

updated: 2026-09-18

- Done: wanted 1 — a favorite button shows the underlying name without its prefix: FX via the new `strip_fx_prefix()` helper, an action via the new `strip_action_prefix()` helper, both in mtt_Shelf.lua. `strip_fx_prefix()` drops "VST: ", "VST3: ", "AU: ", "JS: ", "CLAP: " and the instrument variants ("VSTi: ", "CLAPi: " …) — the trailing `i` is stripped and the base checked against `FORMAT_PREFIXES`; unknown names pass through untouched (e.g. `iZotope Ozone`, `Synth1`). `strip_action_prefix()` drops the leading section prefix ("Script: Toggle play" → "Toggle play"): REAPER prependa sempre un prefisso "<sezione>: " a un nome d'azione, quindi il testo prima della prima ": " è il prefisso e ciò che segue è il nome pulito; un nome senza prefisso passa invariato (stesso comportamento di `strip_fx_prefix` per i nomi sconosciuti). `render_favorite_button` applica `strip_action_prefix()` al posto del nome grezzo per `fav.type == "action"`. Verificate in plain Lua; il percorso di rendering del bottone non è ancora confermato in REAPER.
- Done: wanted 2 — `LoadAllFX` dedups by plugin across formats, keeping one row, with CLAP added at the top of the priority `CLAP > VST3 > AU > VST > JS`. CLAP is detected from the identifier, stripped from the clean name, and set to prio 0 in the priority map. Pure Lua logic only (the `prio < seen.prio` comparison and the `or 5` fallback are unchanged); the in-REAPER enumeration is still untested.
- Done: strip_action_prefix() ora stratta anche il suffisso `.lua` finale, oltre al prefisso di sezione ("aescript: mtt_Shelf.lua" -> "mtt_Shelf"): dopo aver rimosso il prefisso `<sezione>: `, un `name:gsub("%.lua$", "")` elimina il suffisso se presente. I nomi senza prefisso e senza `.lua` restano invariati (es. "Toggle play", "Synth1"). Verificata in plain Lua 5.5.1; il rendering REAPER non è ancora confermato.

## Wanted
