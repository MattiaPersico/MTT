---
name: reaper-lua-imgui
description: "Only when about to write or fix ImGui_* calls in a Lua ReaScript (window, widgets, tables, defer UI loop). Load after reaper-lua."
license: MIT
---

# ReaImGui from Lua

Load `reaper-scripting` and `reaper-lua` first if not loaded. ImGui is in `reaper_lua_docs`.

- A widget's structure is in the note of the `Begin*` that opens it: `get ImGui_BeginTable`, `ImGui_BeginCombo`, `ImGui_BeginMenu`… A signature you did not `get` is guessed: a `search` snippet stops at 600 characters, before the semantics.
- No ReaImGui source to read: it is a compiled extension. Dear ImGui C names (`FLT_MAX`, `ImVec2`, `ImGuiCond_`) do not exist in Lua. Unclear behaviour → the card, or run the script; never a header on disk.

Two call forms, same API — match the one the file uses:

```lua
reaper.ImGui_Foo(ctx, ...)                          -- needs nothing
```
```lua
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'                -- version string is required
ImGui.Foo(ctx, ...)
```

Without the `package.path` line: `module 'imgui' not found`.

- `CreateContext(label)`: label required, called once, outside the loop. No `DestroyContext`, no `CurrentContext`.
- `End*` follows the return of `Begin*`: returns a boolean → `End*` only inside the `if`; returns nothing (`BeginGroup`, `BeginDisabled`) → `End*` always. `BeginDisabled(ctx, cond)` takes the condition. Popups end with `EndPopup` (no `EndPopupModal`), `BeginItemTooltip` with `EndTooltip`. Opposite of Dear ImGui in C++.
- Collapsed is not closed — only `open` ends the loop:
  ```lua
  local function loop()
    local visible, open = ImGui.Begin(ctx, 'Title', true)
    if visible then
      -- ...
      ImGui.End(ctx)
    end
    if open then reaper.defer(loop) end
  end
  ```
- Flags depend on the call form: `reaper.ImGui_Cond_Always()` is a function; `ImGui.Cond_Always` is a number (calling it: `attempt to call a number value`). No enum-style names (`ImGuiWindowFlags.X`).
- Identical labels collide: in loops wrap each row in `PushID(ctx, i)` / `PopID`; one-offs `'Mute##' .. i`.
- An input widget returns the new value; it cannot write into your variable: `local changed, buf = ImGui.InputText(ctx, label, buf)`, no size argument. Assign the second return back to the state it shows.
- `Text(ctx, s)` takes one string — format first. Module-form examples omit `ctx`: never count arguments from an example.
