-- mtt_FmodSync_Mini.lua
-- FMOD Sync Mini: opens FMOD Sync docked in REAPER's docker, where it shows only
-- the takes of the tracks selected in REAPER, with their name, FMOD folder,
-- render settings and Render laid out in width. It is the same window as
-- mtt_FmodSync.lua: floating it is the full FMOD Sync. When the window is
-- already open, this action docks it.

MTT_FMODSYNC_MINI = true
local dir = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]]
dofile(dir .. 'mtt_FmodSync.lua')
