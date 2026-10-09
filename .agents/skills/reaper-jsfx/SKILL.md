---
name: reaper-jsfx
description: "JSFX / EEL2 effects for REAPER: reading, writing or fixing .jsfx (@sample, sliders, gmem; 'un JSFX', 'un effetto'). Load with reaper-scripting."
license: MIT
---

# JSFX: EEL2

Load `reaper-scripting` first if not loaded.

## Corpus gap
`reaper_jsfx_docs` does not cover `gfx_*`, `midi*`, `str*`, user-defined functions, the preprocessor: `verify` flags them as DO NOT EXIST falsely — keep a correct `gfx_rect` / `midisend` and say it is outside the corpus. Any other flag is real (`blocksamp` for `samplesblock`).

## EEL2 rules (not in the corpus)
- No `if`: `cond ? a;` / `cond ? a : b;`. Parentheses group statements: `x ? ( a = 1; b = 2; );` — the value is the last one.
- `;` separates statements, inside parentheses too.
- Variables: doubles, global by default, case-insensitive, declared by use.
- Loops: `loop(n, code)` and `while(code)`, capped around 1,000,000 iterations.
- Comments `//` and `/* */`.

## Sections: code in the wrong one compiles and stays silent
Each special variable's card has a `Context:` line — read it (`spl0 += …` in `@block` writes something nobody reads).

| section | runs | belongs there |
|---|---|---|
| `@init` | load, samplerate change, playback start (`ext_noinit = 1` drops the last two) | allocate memory, read files, build tables; memory re-zeroed unless `@serialize` is non-empty |
| `@slider` | after `@init` and on every parameter change | recompute what `sliderX` feeds |
| `@block` | once per block | timers, `gmem` polling, MIDI, control; `samplesblock` valid here |
| `@sample` | once per sample | `spl0…spl63`, `spl(n)` — audio is made here only |
| `@gfx [w] [h]` | ~30×/s while the UI is open, own thread | `gfx_*`, sized from `gfx_w`/`gfx_h`; shared data unsynchronised |
| `@serialize` | state save/load | `file_var`/`file_mem` on handle 0; don't overwrite it again in `@init` |

- One header directive per line; one `options:` line, space-separated: `options:gmem=NAME maxmem=134217728`. Same for `in_pin` / `out_pin`.
- `file_riff` returns channels and samplerate: use them (a stereo assumption plays mono at double speed).

## Memory: one flat space
~8 million slots, no arrays: `foo[i]` is the slot at (value of `foo`) + i, so `foo` is an address. Unassigned = 0, so `a[i]`, `b[i]`, `c[i]` overlap at 0. Give every buffer an explicit base offset; keep them apart by hand.

## Lua ↔ JSFX: two channels only
No ExtState in JSFX (`ext_getextstate` is invented).
- `gmem[]`: JSFX `options:gmem=name`, then `gmem[i]`; Lua `reaper.gmem_attach(name)` before any `gmem_read(i)` / `gmem_write(i, v)`; `gmem_attach('')` detaches (restore in `atexit`). For arrays.
- Sliders: declared in the header, set from Lua with `TrackFX_SetParam`. For a few visible scalars (hide with `-`, max 256).

Both ends use the same channel; `get` both sides before building on either. Install by name: `TrackFX_AddByName(track, "myfx.jsfx", false, -1)`; find it by name again to remove it (indices shift).

## JSFX generated from Lua
`verify` on the `.lua` never sees the JSFX string. Run the generator on fake data (every unrolled loop ≥ 3 times + one edge case such as mono), save the output as `.jsfx`, read it, verify it against `reaper_jsfx_docs` (a second verify). Reading catches: parentheses unbalanced across strings, names that differ between sections (`play_pos0…N` vs `play_pos[cur]`), `string.format` placeholders vs arguments (`%%` for a literal `%`), `\n` inside `[[ ]]` = a literal backslash-n.

Before replying: generated JSFX verified as its own file (gap flags reported, not "fixed"); every buffer offset; audio in `@sample`; special variables in valid sections; one directive per line; Lua and JSFX on the same channel; verdict per `reaper-scripting` §4.
