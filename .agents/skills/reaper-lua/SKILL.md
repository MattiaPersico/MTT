---
name: reaper-lua
description: "REAPER ReaScript in Lua: reading, writing or fixing .lua scripts (reaper.* calls, defer loops, atexit, actions; 'uno script per REAPER'). Load with reaper-scripting."
license: MIT
---

# ReaScript: Lua

Load `reaper-scripting` first if not loaded.
Corpus `reaper_lua_docs`: Lua signatures only, ImGui included. Never use a C signature: `Main_SaveProject(proj, 0)` passes `0` = TRUE and opens "Save As".
`verify` handles `local r = reaper` and the ImGui module form, checks argument and return counts, literal types, field-name strings and pre-5.4 stdlib, and lists what it did not check.

## Lua traps
- `0` and `1` are TRUE. A `boolean` parameter gets `true` or `false`.
- Lua 5.4: no `math.pow`, `math.log10`, `math.atan2`, `table.getn`, `unpack`, `loadstring`, `setfenv`. Use `x ^ y`, `math.log(x, 10)`, `table.unpack`.
- `math.random(m, n)` takes integers only (a float raises "number has no integer representation"). Float range: `min + math.random() * (max - min)`.
- Every variable `local`, in every branch — otherwise it is a global shared with every running script.
- Mind every return value: `string.format(p:gsub(...))` passes the count too; `(p:gsub(...))` keeps one.
- Field-name strings (`Get/SetMediaItemInfo_Value`, `…TakeInfo_Value`, `…TrackInfo_Value`): copy them from the card; each family has its own set (`D_PLAYRATE` is a take field).
- `*Info_Value` with a `P_` field returns an object, not a number (`D_`, `I_`, `B_` are numbers): `GetMediaItemInfo_Value(item, "P_TRACK")` is the track itself; comparing two raises `attempt to compare two userdata values`. Use `GetMediaItem_Track`; for a number, `GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")` (1-based, 0 = not found, -1 = master).
- A handle dies with its object: a take, source or track pointer from a deleted item is invalid (`bad argument #2 to 'SetMediaItemTake_Source' (PCM_source expected)`, or a crash). Read what the replacement needs and build it **before** `Delete*`. Reordered statements? Say which order and why.
- `#t` ignores index 0: filled `t[0]..t[n-1]` gives `#t == n-1`, and `for i = 0, #t` runs once on `nil` when empty. Loop `for i = 0, n - 1`, or fill from 1 and use `ipairs`.
- `[[` followed by a newline drops that newline: `[[\n<VOLENV\nEGUID ]] .. guid .. [[\nACT 1 -1\n…]]` gives `EGUID <guid>ACT 1 -1` on one line. Only `verify` sees it (`PATTERN`). Add `"\n"` by hand at every join, or build a table of lines + `table.concat(lines, "\n")`.

## Dependencies: check first
```lua
if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('ReaImGui is required (ReaPack: ReaTeam Extensions).', 'Missing dependency', 0)
  return
end
```

## Filesystem
Use REAPER's API — `EnumerateFiles`, `EnumerateSubdirectories`, `file_exists`, `RecursiveCreateDirectory` — not `io.popen` / `os.execute` (same on macOS and Windows, no console). `EnumerateFiles` returns names, not paths: collect them into a table, then act. One separator, built once: `local SEP = reaper.GetOS():find('Win') and '\\' or '/'`.

## Deferred scripts
- Never block: no waiting `while`; return and check again next frame.
- Nothing that can repeat every frame may print or pop up (`ShowConsoleMsg`, `MB` in a `defer` or ImGui callback): return silently, or show the state in the UI (disable the control).
- Register `reaper.atexit` before the loop: it runs on window close, action stop, quit — a UI Stop button does not. Undo there everything installed or changed.
- Every waiting state (`'rendering'`, `'waiting'`): a frame counter, a limit, a visible error past it. Disable the controls that start it while it runs (`BeginDisabled`). Detect completion by a condition you set (your own `RENDER_PATTERN` → that exact path), never "the newest file".

## Pure-Lua logic: run it
A helper with no `reaper.*` (merging intervals, sorting, splitting ranges, offsets) gets nothing from `verify` or the language server, and that is where off-by-ones live. "verify: not run" is not a check.
- `lua` is installed (5.5; REAPER embeds 5.4): run it, no `which`. Same for any question on Lua semantics (patterns, backtracking, precedence, `#`): never answer from memory (Lua patterns have no `|` alternation; the magic characters are `^$()%.[]*+-?`).
- Extract with `sed -n '<from>,<to>p'` into the project's scratch folder (`<scratch>/t.lua`), never retype; drop the function's `local`; stub what it closes over (more than a line or two → too entangled: say so); append calls and run:
  ```sh
  printf '%s\n' 'print(merge_refs({0,1,2},{1,1,1}))' >> <scratch>/t.lua
  lua <scratch>/t.lua
  ```
- Cases: empty table (a loop seeded from `t[1]` dies with `attempt to perform arithmetic on a nil value`), single element, exactly equal boundaries (split items share them: `<=` vs `<` decides whether 3 items merge into 1), wrong order, one range inside another.
- Could not run it? Say it is untested and which cases you reasoned through. Never present it as verified.

Before replying: no pre-5.4 stdlib; booleans `true`/`false`; every variable `local`; `atexit` registered, no blocking, timeouts on waiting states; `APIExists` for extensions; one `SEP`; verify clean, verdict in the reply.
