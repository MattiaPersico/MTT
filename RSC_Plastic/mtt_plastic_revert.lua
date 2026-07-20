-- mtt_plastic_revert.lua
-- Wrapper one-shot: revert del progetto alla versione server. Logica in mtt_plastic_lib.lua.

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

local _, proj_path = reaper.EnumProjects(-1, '')
LIB.doRevertFlow(proj_path)
