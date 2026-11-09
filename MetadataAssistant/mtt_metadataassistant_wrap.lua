-- mtt_metadataassistant_wrap.lua
-- Visual word wrap for a multiline text box when ReaImGui has no wrap flag
-- (ImGui_InputTextFlags_WordWrap, Dear ImGui 1.92.3+). The text the script keeps
-- (the "canonical" text) never gets line breaks it did not have: only the text
-- handed to the widget does, and every added break REPLACES a space, so the
-- widget's text has the same length as the canonical one and differs from it
-- only at those positions.
--
--   display   = wrap(canonical, max_width, measure)       -- what the widget shows
--   canonical = apply_edit(canonical, previous, returned) -- what the user typed
--
-- A Dear ImGui text box ignores the text passed to it while it has focus (it
-- keeps its own copy), so the wrap is refreshed when the box loses focus and is
-- taken from the display text at the moment it gets focus.
-- Pure Lua, no reaper.* calls.

local M = {}

-- text with a "\n" in place of the space before every word that would cross
-- max_width. measure(str) -> width in pixels. Hard "\n" in text are kept; a
-- word wider than max_width stays on a line of its own.
function M.wrap(text, max_width, measure)
  text = tostring(text or "")
  if max_width <= 0 or not text:find(" ", 1, true) then return text end
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local chars = nil
    local ls = 1 -- start of the visual line
    for ws, after in line:gmatch("()%S+()") do
      if ws > ls and measure(line:sub(ls, after - 1)) > max_width then
        -- the space just before the word becomes the break
        chars = chars or { line:byte(1, -1) }
        if line:sub(ws - 1, ws - 1) == " " then
          chars[ws - 1] = 10
          ls = ws
        end
      end
    end
    local shown = line
    if chars then
      -- string.char takes a limited number of arguments: build in chunks
      local parts = {}
      for i = 1, #chars, 4096 do parts[#parts + 1] = string.char(table.unpack(chars, i, math.min(i + 4095, #chars))) end
      shown = table.concat(parts)
    end
    lines[#lines + 1] = shown
  end
  return table.concat(lines, "\n")
end

-- The canonical text after the user changed the widget's text from `previous`
-- to `returned`: the same edit (common prefix and suffix cut off, the middle
-- replaced) applied to `canonical`. canonical and previous have the same
-- length, so the positions carry over. Returns returned unchanged if the
-- lengths do not match (should not happen).
function M.apply_edit(canonical, previous, returned)
  if #canonical ~= #previous then return returned end
  if previous == returned then return canonical end
  local la, lb = #previous, #returned
  local p = 0
  local limit = math.min(la, lb)
  while p < limit and previous:byte(p + 1) == returned:byte(p + 1) do p = p + 1 end
  local s = 0
  limit = math.min(la, lb) - p
  while s < limit and previous:byte(la - s) == returned:byte(lb - s) do s = s + 1 end
  return canonical:sub(1, p) .. returned:sub(p + 1, lb - s) .. canonical:sub(la - s + 1)
end

return M
