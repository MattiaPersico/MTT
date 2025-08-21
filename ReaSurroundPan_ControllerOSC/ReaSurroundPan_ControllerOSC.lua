-- ReaSurroundPan OSC Controller

local major_version = 1
local minor_version = 2

--  OSC USER PREFERENCES  --

local DEVICE_IP = "169.254.200.115"
local DEVICE_LISTENING_PORT = 9001

local REAPER_IP = "169.254.127.88"
local REAPER_LISTENING_PORT = 8008

local OSC_MESSAGE_X = "ReaSurroundPan_X"
local OSC_MESSAGE_Y = "ReaSurroundPan_Y"
local OSC_MESSAGE_TOUCH = "ReaSurroundPan_Touch"

--  OSC USER PREFERENCES  --

local OSC_INITIALISED = false

local OS = reaper.GetOS()

local extension
if OS:match("Win") then
    extension = "dll"
else -- Linux and Macos
    extension = "so"
end

local info = debug.getinfo(1, "S")
local script_path = info.source:match [[^@?(.*[\/])[^\/]-$]]
package.cpath = package.cpath .. ";" .. script_path .. "/socket module/?." .. extension -- Add current folder/socket module for looking at .dll (need for loading basic luasocket)
package.path = package.path .. ";" .. script_path .. "/socket module/?.lua" -- Add current folder/socket module for looking at .lua ( Only need for loading the other functions packages lua osc.lua, url.lua etc... You can change those files path and update this line)ssssssssssssssssssssssssssssssssssss
socket = require("socket.core")
osc = require("osc")
udp = socket.udp()

assert(socket.dns.toip(DEVICE_IP))
-- create a new UDP object
controller_udp = assert(socket.udp())

local osc_x, osc_y = 0, 0
local osc_touch = false

function init_osc(ip, port)
    udp = socket.udp()
    udp:setsockname(ip, port) -- Set IP and PORT
    udp:settimeout(0.0001) -- Dont forget to set a low timeout! udp:receive block until have a message or timeout. values like (1) will make REAPER laggy.

    return true
end

function read_osc()
    for address, values in osc.enumReceive(udp) do
        if address == OSC_MESSAGE_X then
            osc_x = values[1]
        end
        if address == OSC_MESSAGE_Y then
            osc_y = 1 - values[1]
        end
        if address == OSC_MESSAGE_TOUCH then
            if values[1] == 0 then
                osc_touch = false
            else
                osc_touch = true
            end
        end
    end

    return osc_x, osc_y, osc_touch
end

function SetButtonState(set)
    local _, _, sec, cmd = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, set or 0)
    reaper.RefreshToolbar2(sec, cmd)
end

function updatePanners()
    osc_x, osc_y, osc_touch = read_osc()
    local num_sel_tracks = reaper.CountSelectedTracks(0)
    local anySurroundPan = false
    for t = 0, num_sel_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, t)

        -- cicla tutti i fx della traccia
        local fx_count = reaper.TrackFX_GetCount(track)

        for fx = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(track, fx, "")
            if fx_name:match("ReaSurroundPan") then
                --reaper.ShowConsoleMsg('PANNER\n')
                -- cicla tutti i parametri dell'FX
                local param_count = reaper.TrackFX_GetNumParams(track, fx)
                for p = 0, param_count - 1 do
                    local _, param_name = reaper.TrackFX_GetParamName(track, fx, p, "")
                    local ch_prefix, suffix = param_name:match("^(in %d+) ([XYZ]+)$")
                    if ch_prefix and suffix then
                        if suffix == "X" then
                            if osc_touch == true then
                                reaper.TrackFX_SetParam(track, fx, p, 1 - osc_x)
                            else
                                local paramVal = reaper.TrackFX_GetParam(track, fx, p)
                                local msg1 = osc.encode("ReaSurroundPan_X", paramVal)
                                controller_udp:sendto(msg1, REAPER_IP, DEVICE_LISTENING_PORT)
                            end
                        elseif suffix == "Y" then
                            if osc_touch == true then
                                reaper.TrackFX_SetParam(track, fx, p, 1 - osc_y)
                            else
                                local paramVal = reaper.TrackFX_GetParam(track, fx, p)
                                local msg1 = osc.encode("ReaSurroundPan_Y", paramVal)
                                controller_udp:sendto(msg1, REAPER_IP, DEVICE_LISTENING_PORT)
                            end
                        end
                    end
                end
                anySurroundPan = true
            end
        end
    end

    if anySurroundPan then
        local msg1 = osc.encode("IsPannerControllerState", 1)
        controller_udp:sendto(msg1, REAPER_IP, DEVICE_LISTENING_PORT)
    else
        local msg1 = osc.encode("IsPannerControllerState", 0)
        controller_udp:sendto(msg1, REAPER_IP, DEVICE_LISTENING_PORT)
    end
end

function main()
    if OSC_INITIALISED then
        updatePanners()
        reaper.defer(main)
    end
end

OSC_INITIALISED = init_osc(DEVICE_IP, REAPER_LISTENING_PORT)
SetButtonState(1)
main()
reaper.atexit(
    function()
        SetButtonState(0)
    end
)
