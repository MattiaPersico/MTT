local env = reaper.GetSelectedTrackEnvelope(0)
if not env then return end
local n_ai = reaper.CountAutomationItems(env)
local positions = {}

for i = 0, n_ai - 1 do
    if reaper.GetSetAutomationItemInfo(env, i, 'D_UISEL', 0, false) ~= 0 then
        positions[#positions + 1] = reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', 0, false)
    end
end

local anchor = positions[1]
if not anchor then return end
local moveAmount = reaper.GetCursorPosition() - anchor
if moveAmount == 0 then return end

table.sort(positions)
local first, last, step = 1, #positions, 1
if moveAmount > 0 then first, last, step = #positions, 1, -1 end

-- Move the leading edge first so a moved item cannot match a pending source position.
-- Resolve each index again after a write, including when selected items share a position.
for j = first, last, step do
    local source = positions[j]
    local target = source + moveAmount
    if target ~= source then
        for i = 0, n_ai - 1 do
            if reaper.GetSetAutomationItemInfo(env, i, 'D_UISEL', 0, false) ~= 0
                and reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', 0, false) == source then
                reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', target, true)
                break
            end
        end
    end
end
