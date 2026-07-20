-- mtt_plastic_settings.lua
-- Wrapper one-shot: impostazioni. Logica in mtt_plastic_lib.lua.
--
-- Nota: account, server e credenziali Plastic NON si impostano qui.
-- Vivono nella configurazione del client Plastic (client.conf) e cm le usa da solo.

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

LIB.doSettingsFlow()
