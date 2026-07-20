-- mtt_plastic_checkin.lua
-- Wrapper one-shot: check-in del progetto corrente. Logica in mtt_plastic_lib.lua.

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

local _, proj_path = reaper.EnumProjects(-1, '')
LIB.doCheckinFlow(proj_path)
