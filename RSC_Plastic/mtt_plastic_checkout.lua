-- mtt_plastic_checkout.lua
-- Wrapper one-shot: update + checkout esclusivo (lock). Logica in mtt_plastic_lib.lua.

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

local _, proj_path = reaper.EnumProjects(-1, '')
LIB.doCheckoutInteractive(proj_path)
