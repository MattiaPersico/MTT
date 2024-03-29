
--[[
This script was created by Mattia Persico in 2024.
It uses a dependency originally developed by David Ng (2010) and Steve J. Fortune (1987)
and modified by Mattia Persico (2024), which is under the MIT license.
This dependency is used to calculate the Voronoi diagram.
For information about the MIT-licensed dependency, refer to the file voronoi.lua.
]]

-- Appunti:
-- dare un path sensato al file voronoi.lua attualmente viene letto in un path mio
-- aggiungere supporto a fx dentro container
-- provare ad aggiungere modalita che lavora solo su tracce selezionate
-- sistema filtri specifico oppure...
-- ... sistema di edit snapshots
-- Script Name and Version


local major_version = 0
local minor_version = 32

local name = 'Metasurface ' .. tostring(major_version) .. '.' .. tostring(minor_version)

local PLAY_STOP_COMMAND = '_4d1cade28fdc481a931786c4bb44c78d'
local PLAY_STOP_LOOP_COMMAND = '_b254db4208aa487c98dc725e435e531c'
local SAVE_PROJECT_COMMAND = '40026'

local PREF_WINDOW_WIDTH = 350
local PREF_WINDOW_HEIGHT = 420

local MAX_MAIN_WINDOW_WIDTH = 600
local MAX_MAIN_WINDOW_HEIGHT = 600

local MAIN_WINDOW_WIDTH = 500
local MAIN_WINDOW_HEIGHT = 500

local WIDTH_OFFSET = 8
local HEIGHT_OFFSET = 67

local ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
local ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET

local IGNORE_PARAMS_PRE_SAVE_STRING = 'midi'
local IGNORE_PARAMS_POST_SAVE_STRING = ''
local IGNORE_FXs_PRE_SAVE_STRING = ''
local IGNORE_FXs_POST_SAVE_STRING = ''
local IGNORE_TRACKS_PRE_SAVE_STRING = ''
local IGNORE_TRACKS_POST_SAVE_STRING = ''

local LINK_TO_CONTROLLER = false
local CONTROL_TRACK = nil
local CONTROL_FX_INDEX = nil
local canWriteControllerAutomation = false

local ENABLE_WINDOW_RESIZE = true

local INTERPOLATION_MODE = 0

local main_window_width = MAIN_WINDOW_WIDTH -- current values during loop
local main_window_height = MAIN_WINDOW_HEIGHT -- current values during loop

local colorPickerWindowState = false

function ensureGlobalSettings()
    nomeFile = reaper.GetResourcePath() .. '/Scripts/MTT_Scripts/ReMS/ms_global_settings'
    local path = string.match(nomeFile, "(.+)/[^/]*$")
    if path then
        -- Usa virgolette per gestire i percorsi con spazi su macOS
        os.execute("mkdir -p \"" .. path .. "\"")
    end

    local file = io.open(nomeFile, "r")

    if file then
        file:close()
    else
        file = io.open(nomeFile, "w")
        if file then

            file:write("IGNORE_PARAMS_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_PARAMS_PRE_SAVE_STRING) .. "\n")
            file:write("IGNORE_FXs_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_FXs_PRE_SAVE_STRING) .. "\n")
            file:write("IGNORE_TRACKS_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_TRACKS_PRE_SAVE_STRING) .. "\n")
            file:write("INTERPOLATION_MODE = " .. string.format("%q", INTERPOLATION_MODE) .. "\n")

            file:close()
        else
            print("Errore nella creazione del file")
        end
    end

    return nomeFile
end

--local voronoi = require(reaper.GetResourcePath() .. "/Scripts/MTT_Scripts/ReMS/voronoi")
--local voronoi = require(reaper.GetResourcePath() .. "/Scripts/MTT/ReMS/voronoi")
if reaper.file_exists(reaper.GetResourcePath() .. "/Scripts/MTT/ReMS/voronoi.lua") then
    require(reaper.GetResourcePath() .. "/Scripts/MTT/ReMS/voronoi")
  else
    require(reaper.GetResourcePath() .. "/Scripts/MTT_Scripts/ReMS/voronoi")
  end


----------------------------------------------------------------------- OSC -----------------------------------------------------------------------
--[=[ 

local OSC_CONTROLLED = false                -- va messo nelle preferenze
local OSC_SERVER_IP = "169.254.139.153"     -- va messo nelle preferenze
local OSC_LISTEN_PORT = 8003                -- va messo nelle preferenze

-- Load the socket module
local opsys = reaper.GetOS()
local extension

local OSC_X, OSC_Y = 0, 0

if opsys:match('Win') then
  extension = 'dll'
else -- Linux and Macos
  extension = 'so'
end

local info = debug.getinfo(1, 'S');
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]];
package.cpath = package.cpath .. ";" .. script_path .. "/socket module/?."..extension  -- Add current folder/socket module for looking at .dll (need for loading basic luasocket)
package.path = package.path .. ";" .. script_path .. "/socket module/?.lua" -- Add current folder/socket module for looking at .lua ( Only need for loading the other functions packages lua osc.lua, url.lua etc... You can change those files path and update this line)

-- Get socket and osc modules
local socket = require('socket.core')
local osc = require('osc')

-- Get UDP
local udp = assert(socket.udp())
assert(udp:setsockname(OSC_SERVER_IP, OSC_LISTEN_PORT)) -- Set IP and PORT
udp:settimeout(0.0001) -- Dont forget to set a low timeout! udp:receive block until have a message or timeout. values like (1) will make REAPER laggy.

local function updateOSC()

    for address, values in osc.enumReceive(udp) do
        --[[ print('address: ', address)
        print('This message haves '..#values..' values:')
        for k, v in ipairs(values) do
          print('    ', v)
          x = v
        end ]]
        if #values == 2 then
            OSC_X = values[1]
            OSC_Y = values[2]
        end
  
    end

    reaper.defer(updateOSC)
end

----------------------------------------------------------------------- OSC -----------------------------------------------------------------------
--]=]


local GLOBAL_SETTINGS = ensureGlobalSettings()

-- Funzione EEL per i Vincoli delle Dimensioni della Finestra
local sizeConstraintsCallback = [=[
a = 0
]=]

local CONTROLLER = [=[
desc:mtt_metasurface_controller

slider1: 0.5 <0,1,0.0001>mtt_mc_x_pos
slider2: 0.5 <0,1,0.0001>mtt_mc_y_pos
    
@init
    cursor_x = slider1 * gfx_w;
    cursor_y = slider2 * gfx_h;
]=]

local save_icon_binary = 'iVBORw0KGgoAAAANSUhEUgAAAB8AAAAeCAYAAADU8sWcAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAB+gAwAEAAAAAQAAAB4AAAAAvt2RRQAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDYuMC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KGV7hBwAAAmVJREFUSA3lVztLA0EQnr0T0wTRQoIWFgFrwSgIooJYKFoZ7dR/oE3ER6NoZcTOf+CjirHVQgQVEcRYaBkIaGEINhLSRLisO4nZm93ceTGmELIQ7pvd2fl2Hnc7AWjUwdwcj6TT/QDGDAPeBwx6gUOrm64yz+BD6D5yYA8mt2K7nZ0PyjoRKsgXk0lfs79lW5BGhJ5JdGuBFgDby+eym/vd3XndgEKOxD5/yy0AD+mKf5NZQhxgUD+AQY2ix/UnRgYeEk5tUS7Ekhxz/B1qqcMLBXiJxeB+aREupyblPAU3C/OAPxwXE+OQOjqiywTz5ZW3tz4yAU22YMyIE8ocI3FifRU+np5tFQeUf39XZlPHJfLg3JwyLwTTYuaseMoClJ4Xq5qov8bjnsREXYF4AKcI6By256XXSRrJ3FxL/BPwtbc7LjtGADnIsMm19ziXShE1dzh0cOi6iAdQwq9x2OSaiYIlXlFtYEHVc8ic19NotbYal9w15zR0Y2fnVPTE1dZG44b9f3pumPIz75ljNwUvG7bn2IGQ4Q8GiVQbrLChcdjVLlofQTFapgkMDUM2mSyK1VZveW/5GRgeKcPik3FI0AnpOfZcdKErHIa2nh469SuMe7ump5U9Oodso0rNBLsT2jLZeKe/np5C5voK8KJx+t5T65hjDDV6jMTMkL6hmmXwwgBtKCU5rkbSmai4c1cQ13+w6F5HYI3aVY72mctuiG5TyQtVrh0XG8hNfb9Cjt0ldpniAFGhWHmn6ru9ZYtz2HHqXHGrEnZqq1QDRhhbH84g9Js/DVjVWFwGt05ojqn9xsZfGVrF0ppqd+IAAAAASUVORK5CYII='
local cog_icon_binary = 'iVBORw0KGgoAAAANSUhEUgAAAB8AAAAeCAYAAADU8sWcAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAB+gAwAEAAAAAQAAAB4AAAAAvt2RRQAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDYuMC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KGV7hBwAAA2xJREFUSA3lV01IVFEUPm8mtIU/CVr+ZEL+RFKL8m8RCioIiW2sqEW5VagEf5AoSAqKDMuFBrXV6IeiFrm1hdJC01oISiMTkuFoCjaTixSm1/mevjv3XueNg9rKA8937j3fOd/ce86570q0W8VwWniLz1dE5DpnkFlIBp0kk/Y5YZV5g34x9rNJxqjbDL5+kJ4+qtilwQbya1NTsTFxCXeYtIVxbgm7FTVIZHSuLAfau3NzV/QACjmIY+MSPhKZBTpwe2NjjH/AKf0HuOSgWPHOE4PBLOBF3Za5oAty5Hh9q3XMhvFvr5cGL16wHujRidnaNjtbKGMFOYqLDVHl2DcwQKt+v/X4PgzI8SLp7qDhPi8D9tgDq6rtgfReGh8nz9MnlJB3hLLr6mhxZJjmhwYF4ufQEMVlZVFycQl5e3sp4PlKeQ0NlHTsuMDYis4hCq51bm4pXDsNX71CYmsNhpumHUt9S7b47Gwq6Xms2jHiNuxMTU2yDaFtd+hjrFiIEzEAkk3xEc7AqGdFiFwGSTq2mrCqaIWxlk8UeJFzJyxyLK8KuMT8fMqsOWO5zPS/J//ERMidd2BxZITSq6pCcw6aIznyjKqWiwsxQFz08JEIl1peTp+am8g/OSnmvj3ro+XpaUqrrCTk30kcyb/cvGG1ku6YWVOjT9FB3gWZ/M/CAn1/95bmuA3LXr7agLcnNs25Dfwfb0fyE3fv0aHaWtqbkqLwzvT3K2MMfnDeZYEPfBEjkjhuO3KFBwfIRFeXiIHiQo6x1RAQy1uOucOXLm+v4BAEgpPLajWpj0GmE66h+S+3WnJxsRhGUhy33XbCkam3mm0L++Yf6e1jnygkRI4bSBjBWS0k0mEj2QIej3BRFI0jRM5XHwW4PsBHIj4nhzKqq6ns+QvKb2pWihDFhTnYMk5XW3WSV18fLhQZJo3JBlFwuHPxV6dCNkLH16mku0dM4+TCAYI+huwvLRXFdbSxUeDCKeCQ50Mrp79v2MB3rs0FJ1dMYqL1pFVUbu6whgi6zCA4hChfjBbffAevvk1Yd1QxOjrTDlyXQ0orJ1pdDtziXlHyIoO3rlsXyHbdXyHH7RK3TP4BHQyMKgV6QG0c5M67H+7mCpyy7bLj2oXSdRZXH9OgAv0iIGMVndsJVY3iQo4j/dOg+O2qwT/WvyYZTab97wAAAABJRU5ErkJggg=='
local bin_icon_binary = 'iVBORw0KGgoAAAANSUhEUgAAAB8AAAAeCAYAAADU8sWcAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAB+gAwAEAAAAAQAAAB4AAAAAvt2RRQAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDYuMC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KGV7hBwAAAlNJREFUSA3tl89LG0EUx7+zK/4AkYJijRRBROixJAYK3urFgpdae2jA/0BPKaWXKurFSE71T/CY2t6lV+lBrd56EMH20LVSVESIvzbTeStO3s6a3UQTEXQgyfs17zNvZrJ5Ae7rEKUKTztOErBGBGQfBOKQeFQq1mcXOFCxPyTEqi3d3Fxn56rPz5QAfHxzs6G+uWVaQdMqzmax1xFdQGRPjg4n53t7T8wEPjiBG5pblgGZMANvpos1tYB+cwEWT0oVVx9MBJlQRU1xFsm6cjpjAfFd2SK3+vfXL9haWPBy9YyOouvVsCdHvLmWLDznd4BVbo2UAybAr8VFuPm899rO5SKY2m27wn6jNSXUXSrerb5UjM+NiY/4t7JiWC/U0/19fHs5qH1tySSeTc9onQsmo1g5fZ1qPQyGPvN3zo6sNZvyZ2Mdmlms/DbIBkOfuWEPqD/nP2FvfR3Hu7uQrnp2sCFsG43t7WiNx/F0bJx5wsWyK3eWlpB3nACY0tNiyPdHxVQyyoYXzs8j8xbOziJjeEDZcD6pWvIDvFo7WVGeO7Lt1IHUehiMYuWq9Qlj201NYW7PFxUjJNZ4Eg2nnos7TDn2YsA0BfTYQHiMydBwoPBZZfM/N1n67lQKT4aGcFV1ZCNf99sUmxEQVTPhEkMP/QtDlrTzN6N+c99rb1UFkcnGHn/gKVnlwOnR4YTqrHznwoOvL3sN5KQ53wen7pK6TLWAjAoseQRmkhDdlRKzV3WuNMe37TzJRUNpvabWRwokKvnTQLeaLhedMW8Yef77Lf8Hv8e0J8p3FsoAAAAASUVORK5CYII='
local link_icon_binary = 'iVBORw0KGgoAAAANSUhEUgAAAB8AAAAeCAYAAADU8sWcAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAB+gAwAEAAAAAQAAAB4AAAAAvt2RRQAAAAlwSFlzAAALEwAACxMBAJqcGAAAAVlpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDYuMC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgogICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpEZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KGV7hBwAAAvNJREFUSA3lVs9rU0EQ/jZPmksJTeshKf5AJClIBNsYEDyZczw1gl76H3gxvRVbrBZU0pN/gblUMD2ZmxJPIm3aKsRLG6RUheQQGwm9pPD63HnJ27dv+14rJu/UvezM7Ox8M7MzywBndTGvwHP1egoIZBmMm2CYgoERL12HnOEP190ywDY0Q3/7cnx8w3EuMcfAH9ZqwaHh0CIHzXE9TdL9H1IHWL5z0F54FYt1VAMOcAIODoc+AUZSVeyPZ5vcgduqAwHZKEU8eGBCMJI8qCcyFtEicnpjBvaZy/pNtYph8XrAOLol14AUeSDrIzA5oOlMu2d5QrsAN6taPvGBVjEEuNlOPgA6TFLLSuucoF36uPWtir1iEe2dHRy2WqbqWDKJyWdL4hoRX+bm8Htr05QNhcMIxeO4nM0inLju0FP/ChvcqYbdlRV8L7xWpKez5GRzbQ3N9XVcnZnBlfsPPC+5greqVROYaRqi6TQuZO6a0XhZmVyyM0FZ+lV6h3q5zG0UMJJIHM9Az5D95pLlvdWiyRHwtUe5E4GlayZJKac7kTtp3t4GfhRXVRXBu0ZO3tOiiOX1df4xmpWKLBL0+VQKNxafCv5iJoP6h/do17q2xIFEuEYunftKukZOqaOiobejFFpLjsySee0/SyXzKBSLe6nAFZzahMCpaPizgVIYmpjwNCIftLe3QcCNj2X+eTOz5eRzmRZ/+2y9wWHstfuGWq1gFo0tBcameJ9L1U1ncp8LXQ7s1mr5aERgukZOBqg/qU2oWqloOvv7wu5JRHB0FJTqS9lpzxaz7gsvZhuNlvoDWUoD2/mUk49EwpY9u9r56GMJ/dqZge4f3AMQ4DRz+QVq2VUxBDhwRN8an7l8W3yY0LtfZw9CgC9HoxXu2bJv0HyQlKcYwhHgxBwetOd5czreheT9L3OAXFDtOMBpuqQpkzvwgisO4gl0/kk9d5tcyRHRaqpX3YEyME2jj8GQ/Oc25O1EVU3FRW+splrFOZv8X4N/90UIdfDIAAAAAElFTkSuQmCC'

function base64_decode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

function ensureIcons()
    local saveIconFile = reaper.GetResourcePath() .. '/Scripts/MTT_Scripts/ReMS/icons/save_icon.png'

    local path = string.match(saveIconFile, "(.+)/[^/]*$")
    if path then
        -- Usa virgolette per gestire i percorsi con spazi su macOS
        os.execute("mkdir -p \"" .. path .. "\"")
    end

    local file = io.open(saveIconFile, "rb")

    if file then
        file:close()
    else
        file = io.open(saveIconFile, "wb")
        if file then

            file:write(base64_decode(save_icon_binary))
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end


    local binIconFile = reaper.GetResourcePath() .. '/Scripts/MTT_Scripts/ReMS/icons/bin_icon.png'

    local file = io.open(binIconFile, "rb")

    if file then
        file:close()
    else
        file = io.open(binIconFile, "wb")
        if file then

            file:write(base64_decode(bin_icon_binary))
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end

    local cogIconFile = reaper.GetResourcePath() .. '/Scripts/MTT_Scripts/ReMS/icons/cog_icon.png'

    local file = io.open(cogIconFile, "rb")

    if file then
        file:close()
    else
        file = io.open(cogIconFile, "wb")
        if file then

            file:write(base64_decode(cog_icon_binary))
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end

    local linkIconFile = reaper.GetResourcePath() .. '/Scripts/MTT_Scripts/ReMS/icons/link_icon.png'

    local file = io.open(linkIconFile, "rb")

    if file then
        file:close()
    else
        file = io.open(linkIconFile, "wb")
        if file then

            file:write(base64_decode(link_icon_binary))
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end

    return reaper.ImGui_CreateImage(saveIconFile), reaper.ImGui_CreateImage(binIconFile), reaper.ImGui_CreateImage(cogIconFile), reaper.ImGui_CreateImage(linkIconFile)

end

local save_icon, bin_icon, cog_icon, link_icon = ensureIcons()

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8')
local ctx = reaper.ImGui_CreateContext(name)
local comic_sans = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 18)
local comic_sans_bigger = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 21)
local comic_sans_smaller = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 17)
local new_line_font = reaper.ImGui_CreateFont('/System/Library/Fonts/Supplemental/Comic Sans MS.ttf', 2)

reaper.ImGui_Attach(ctx, comic_sans)
reaper.ImGui_Attach(ctx, comic_sans_bigger)
reaper.ImGui_Attach(ctx, comic_sans_smaller)
reaper.ImGui_Attach(ctx, new_line_font)

local grouped_parameters = {}
local points_list = {}
local snapshot_list = {}
local balls = {}

local ball_default_color = reaper.ImGui_ColorConvertDouble4ToU32(1,1,1, 1)

--local is_new_value,filename,sectionID,cmdID,mode,resolution,val,contextstr = reaper.get_action_context()

local fx_snapshot = {
    guid = 0,
    param_list = {},
    param_index_list = {}
}

function fx_snapshot:new(guid)
    local instance = setmetatable({}, {__index = self})
    instance.param_list = {}
    instance.guid = guid or 0
    instance.param_index_list = {}
    return instance
end

local track_snapshot = {
    guid = 0,
    fx_list = {}
}

function track_snapshot:new(guid)
    local instance = setmetatable({}, {__index = self})
    instance.fx_list = {}
    instance.guid = guid or 0
    return instance
end

local proj_snapshot = {
    x = 0,
    y = 0,
    name,
    track_list = {},
    color = reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 0.2),
    assigned = false,
    range = 0.5
}

function proj_snapshot:new(x, y, name, color, range)
    local instance = setmetatable({}, {__index = self})
    instance.x = x or 0
    instance.y = y or 0
    instance.name = name
    instance.track_list = {}
    instance.color = color or reaper.ImGui_ColorConvertDouble4ToU32(math.random(), math.random(), math.random(), math.random())
    instance.assigned = false
    instance.range = range or 0.5
    return instance
end

local parameter = {
    track = nil,
    fx_index = nil,
    param_list_index = nil,
    param_value = nil,
    snap_index = nil
}

function parameter:new(track, fx_index, param_list_index, param_value, snap_index)
    local instance = setmetatable({}, {__index = self})
    instance.track = track or nil
    instance.fx_index = fx_index or nil
    instance.param_list_index = param_list_index or nil
    instance.param_value = param_value or nil
    instance.snap_index = snap_index or nil
    return instance
end


LAST_TOUCHED_BUTTON_INDEX = nil

DRAG_X = 0
DRAG_Y = 0

-- Variabili per lo smoothing
local smoothing = 5
local smoothing_max_value = 20
local smoothing_fader_value = 0.3
local range_fader_value = 0.5
local targetX, targetY = 0, 0 -- Coordinate target
local lastUpdateTime = reaper.time_precise()
local needToInitSmoothing = true
local CURRENT_DRAG_X = 0
local CURRENT_DRAG_Y = 0

local is_name_edited = false
local preferencesWindowState = false

local PROJECT_NAME = reaper.GetProjectName(0)
local PROJECT_PATH = reaper.GetProjectPath(0)

local need_to_save = false
local isInterpolating = false
local DRAGGING_BALL = nil
local quit = false
local PLAY_STATE = false

local needToUpdateVoronoi = true

function serializeSnapshots(obj)
    local luaType = type(obj)
    if luaType == "number" or luaType == "boolean" then
        return tostring(obj)
    elseif luaType == "string" then
        return string.format("%q", obj)
    elseif luaType == "table" then
        local isList = true
        local elements = {}
        for k, v in pairs(obj) do
            if type(k) ~= "number" then isList = false end -- Semplice verifica per distinguere le liste dalle mappe
            local serializedValue = serializeSnapshots(v)
            if isList then
                table.insert(elements, serializedValue)
            else
                local key = type(k) == "string" and string.format("%q", k) or tostring(k)
                table.insert(elements, "[" .. key .. "] = " .. serializedValue)
            end
        end
        if isList then
            return "{" .. table.concat(elements, ", ") .. "}"
        else
            return "{ " .. table.concat(elements, ", ") .. " }"
        end
    else
        return "\"[unsupported type]\""
    end
end

function saveToFile(filePath, data)
    local file, err = io.open(filePath, "w") -- Apre il file in modalità scrittura
    if file then

        file:write("IGNORE_PARAMS_POST_SAVE_STRING = " .. string.format("%q", IGNORE_PARAMS_POST_SAVE_STRING) .. "\n")
        file:write("IGNORE_FXs_POST_SAVE_STRING = " .. string.format("%q", IGNORE_FXs_POST_SAVE_STRING) .. "\n")
        file:write("IGNORE_TRACKS_POST_SAVE_STRING = " .. string.format("%q", IGNORE_TRACKS_POST_SAVE_STRING) .. "\n")
        file:write("LINK_TO_CONTROLLER = " .. string.format("%q", LINK_TO_CONTROLLER) .. "\n")
        file:write(data) -- Scrive i dati serializzati nel file
        file:close() -- Chiude il file
    end

    local file, err = io.open(GLOBAL_SETTINGS, "w") -- Apre il file in modalità scrittura
    if file then
        
        file:write("IGNORE_PARAMS_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_PARAMS_PRE_SAVE_STRING) .. "\n")
        file:write("IGNORE_FXs_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_FXs_PRE_SAVE_STRING) .. "\n")
        file:write("IGNORE_TRACKS_PRE_SAVE_STRING = " .. string.format("%q", IGNORE_TRACKS_PRE_SAVE_STRING) .. "\n")
        file:write("INTERPOLATION_MODE = " .. string.format("%q", INTERPOLATION_MODE) .. "\n")
        file:close() -- Chiude il file
    end
end

function writeSnapshotsToFile(filename)
    local data = serializeSnapshots(snapshot_list)
    saveToFile(filename, data)
end

function loadFromFile(filename)

    local ignoreParamsPostSaveString = ''
    local ignorePostSaveFxsString = ''
    local ignorePostSaveTracksString = ''
    local linkToControllerBool = false
    local data = nil

    local ignoreParamsPreSaveString = 'midi'
    local ignorePreSaveFxsString = ''
    local ignorePreSaveTracksString = ''
    local interpolationModeInt = 0

    local local_settings, err = io.open(filename, "r")
    
    if local_settings then
        local ignoreParamsPostSave = local_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local ignorePostSaveFxs = local_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local ignorePostSaveTracks = local_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local linkToController = local_settings:read("*l")
        

         ignoreParamsPostSaveString = ignoreParamsPostSave:match("^IGNORE_PARAMS_POST_SAVE_STRING = (.+)$")
        if ignoreParamsPostSaveString then
            ignoreParamsPostSaveString = load("return " .. ignoreParamsPostSaveString)()
        end

         ignorePostSaveFxsString = ignorePostSaveFxs:match("^IGNORE_FXs_POST_SAVE_STRING = (.+)$")
        if ignorePostSaveFxsString then
            ignorePostSaveFxsString = load("return " .. ignorePostSaveFxsString)()
        end

         ignorePostSaveTracksString = ignorePostSaveTracks:match("^IGNORE_TRACKS_POST_SAVE_STRING = (.+)$")
        if ignorePostSaveTracksString then
            ignorePostSaveTracksString = load("return " .. ignorePostSaveTracksString)()
        end

         linkToControllerBool = linkToController:match("^LINK_TO_CONTROLLER = (.+)$")
        if linkToControllerBool then
            linkToControllerBool = load("return " .. linkToControllerBool)()
        end

        local dataString = local_settings:read("*a") -- Legge il resto del file per i dati serializzati

        local dataFunction = load("return " .. dataString)

        if not dataFunction then
            local_settings:close()
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
            loadFromFile(filename)
        else
            data = dataFunction()
        end

        local_settings:close()
    end

    local global_settings, err = io.open(GLOBAL_SETTINGS, "r")
    if global_settings then
        local ignoreParamsPreSave = global_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local ignorePreSaveFxs = global_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local ignorePreSaveTracks = global_settings:read("*l") -- Legge la prima linea che contiene IGNORE_PARAMS_PRE_SAVE_STRING
        local interpMode = global_settings:read("*l")
        
        global_settings:close()
    
         ignoreParamsPreSaveString = ignoreParamsPreSave:match("^IGNORE_PARAMS_PRE_SAVE_STRING = (.+)$")
        if ignoreParamsPreSaveString then
            ignoreParamsPreSaveString = load("return " .. ignoreParamsPreSaveString)()
        end
    
         ignorePreSaveFxsString = ignorePreSaveFxs:match("^IGNORE_FXs_PRE_SAVE_STRING = (.+)$")
        if ignorePreSaveFxsString then
            ignorePreSaveFxsString = load("return " .. ignorePreSaveFxsString)()
        end
    
         ignorePreSaveTracksString = ignorePreSaveTracks:match("^IGNORE_TRACKS_PRE_SAVE_STRING = (.+)$")
        if ignorePreSaveTracksString then
            ignorePreSaveTracksString = load("return " .. ignorePreSaveTracksString)()
        end

        interpolationModeInt = interpMode:match("^INTERPOLATION_MODE = (.+)$")
        if interpolationModeInt then
            interpolationModeInt = load("return " .. interpolationModeInt)()
        end
    end

    if not ignoreParamsPreSaveString then ignoreParamsPreSaveString = 'midi' end
    if not ignoreParamsPostSaveString then ignoreParamsPostSaveString = '' end
    if not ignorePreSaveFxsString then ignorePreSaveFxsString = '' end
    if not ignorePostSaveFxsString then ignorePostSaveFxsString = '' end
    if not ignorePreSaveTracksString then ignorePreSaveTracksString = '' end
    if not ignorePostSaveTracksString then ignorePostSaveTracksString = '' end
    if not linkToControllerBool then linkToControllerBool = false end
    if not interpolationModeInt then interpolationModeInt = 0 end

    return data, ignoreParamsPreSaveString, ignoreParamsPostSaveString, ignorePreSaveFxsString, ignorePostSaveFxsString, ignorePreSaveTracksString, ignorePostSaveTracksString, linkToControllerBool, interpolationModeInt
end

function GetNormalizedMousePosition()
    local mouseX, mouseY = GetMouseCursorPositionInWindow() -- Usa la tua funzione esistente
    local normalizedX = mouseX / ACTION_WINDOW_WIDTH
    local normalizedY = mouseY / ACTION_WINDOW_HEIGHT
    return normalizedX, normalizedY
end

function gui_loop()

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), reaper.ImGui_ColorConvertDouble4ToU32(0.45, 0.45, 0.45, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2)) 
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2)) 
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGrip(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ResizeGripHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.14, 0.14, 0.14, 2)) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.18, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.25, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 2))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.13, 0.13, 0.13, 2))
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 2))
  
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.35, 0.35, 2))
  
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.09, 0.09, 0.09, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1))
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5) 
  
    reaper.ImGui_PushFont(ctx, comic_sans)

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MAX_MAIN_WINDOW_WIDTH, MAX_MAIN_WINDOW_HEIGHT, 900, 900, reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback))

    local flags

    if ENABLE_WINDOW_RESIZE then
        flags =  
          reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoScrollbar()
        | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        | reaper.ImGui_WindowFlags_NoDocking()  
    else
        flags = 
          reaper.ImGui_WindowFlags_NoResize() 
        | reaper.ImGui_WindowFlags_NoCollapse()
        | reaper.ImGui_WindowFlags_NoScrollbar()
        | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        | reaper.ImGui_WindowFlags_NoMove()
        | reaper.ImGui_WindowFlags_NoDocking() 
    end
    
    local mw_visible, mw_open = reaper.ImGui_Begin(ctx, name .. '  -  ' .. string.gsub(PROJECT_NAME, '.RPP', ""), true, flags)

    MAIN_WINDOW_WIDTH, MAIN_WINDOW_HEIGHT = reaper.ImGui_GetWindowSize(ctx)
    ACTION_WINDOW_WIDTH = MAIN_WINDOW_WIDTH - WIDTH_OFFSET
    ACTION_WINDOW_HEIGHT = MAIN_WINDOW_HEIGHT - HEIGHT_OFFSET
    
    main_window_x, main_window_y = reaper.ImGui_GetWindowPos(ctx)
    local tmp_main_window_w, tmp_main_window_h = reaper.ImGui_GetWindowSize(ctx)

    if tmp_main_window_w ~= main_window_width then needToUpdateVoronoi = true end
    if tmp_main_window_h ~= main_window_height then needToUpdateVoronoi = true end

    main_window_w = tmp_main_window_w
    main_window_h = tmp_main_window_h
  
    if mw_visible then

        if colorPickerWindowState then
            local flags = reaper.ImGui_WindowFlags_NoCollapse()
            --reaper.ImGui_SetNextWindowFocus(ctx)
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, 300, 268, 300 * 1.5, 268 * 1.55, reaper.ImGui_CreateFunctionFromEEL(sizeConstraintsCallback))
            local cpw_visible, cpw_open = reaper.ImGui_Begin(ctx, 'Color Picker', flags)
      
            if cpw_visible then
                colorPickerWindow()
                reaper.ImGui_End(ctx)
                
                if cpw_open == false then
                    colorPickerWindowState = false
                end
    
            end
          end
          
      mainWindow()

      reaper.ImGui_End(ctx)


      pref_window_x = main_window_x + main_window_w
      pref_window_y = main_window_y
        
      

      if preferencesWindowState then
  
        reaper.ImGui_SetNextWindowPos(ctx, pref_window_x, pref_window_y)
        reaper.ImGui_SetNextWindowSize(ctx, PREF_WINDOW_WIDTH, PREF_WINDOW_HEIGHT)--, reaper.ImGui_Cond_FirstUseEver())
  
        local pw_visible, pw_open = reaper.ImGui_Begin(ctx, 'Preferences',false, reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoCollapse())
  
        if pw_visible then
          preferencesWindow()
          reaper.ImGui_End(ctx)
          
        end
      end

      reaper.ImGui_PopFont(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)  
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
      reaper.ImGui_PopStyleVar(ctx)
  
    end

    if mw_open and PROJECT_NAME ~= '' and quit == false then
        reaper.defer(loop)
    end

end

function colorPickerWindow()
    local color = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,1)
    local canEdit = false

    if snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then
        color = snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color
        canEdit = true
    end
    --reaper.ImGui_WindowFlags_TopMost()
    --reaper.ImGui_ColorEditFlags_AlphaPreview()
    local flags =   reaper.ImGui_ColorEditFlags_NoBorder() |
                    reaper.ImGui_ColorEditFlags_NoDragDrop() |
                    reaper.ImGui_ColorEditFlags_NoSidePreview() |
                    reaper.ImGui_ColorEditFlags_NoLabel() | 
                    reaper.ImGui_ColorEditFlags_NoInputs() | 
                    reaper.ImGui_ColorEditFlags_AlphaBar() | 
                    reaper.ImGui_ColorEditFlags_AlphaPreview() | 
                    reaper.ImGui_ColorEditFlags_NoOptions() | 
                    reaper.ImGui_ColorEditFlags_NoSmallPreview() | 
                    reaper.ImGui_ColorEditFlags_NoPicker()

    reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetWindowWidth(ctx) - 20)
    local retval, col_rgba = reaper.ImGui_ColorPicker4(ctx, '##snap_cp', color, flags)

    if retval and canEdit then
        snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color = col_rgba
    end

end

function loop()

    gui_loop()
    
    if not isInterpolating then
        if reaper.GetProjectName(0) ~= PROJECT_NAME then
            onExit()
            initMS()
        end

        if reaper.IsProjectDirty(0) == 1 then need_to_save = true end

        if reaper.IsProjectDirty(0) == 0 and need_to_save == true then
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
            need_to_save = false
        end
    end

end

function GetMouseClickPositionInWindow(ctx, button)
    -- Ottieni la posizione del click del mouse
    local mouseClickedX, mouseClickedY = reaper.ImGui_GetMouseClickedPos(ctx, button)

    -- Ottieni la posizione dell'angolo in alto a sinistra della finestra ImGui
    local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola la posizione del click del mouse relativa alla finestra ImGui
    local relativeClickPosX = mouseClickedX - windowPosX
    local relativeClickPosY = mouseClickedY - windowPosY

    -- (Opzionale) Controlla se il click è all'interno della finestra
    local windowWidth, windowHeight = reaper.ImGui_GetWindowSize(ctx)
    if relativeClickPosX >= 0 and relativeClickPosX <= windowWidth and
       relativeClickPosY >= 0 and relativeClickPosY <= windowHeight then
        -- Il click è all'interno della finestra
        return relativeClickPosX, relativeClickPosY
    else
        -- Il click è fuori dalla finestra, puoi gestire questo caso come preferisci
        return nil, nil
    end
end

function GetMouseCursorPositionInWindow()
    local mouseClickedX, mouseClickedY = reaper.ImGui_GetMousePos(ctx)

    -- Ottieni la posizione dell'angolo in alto a sinistra della finestra ImGui
    local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola la posizione del click del mouse relativa alla finestra ImGui
    local relativeClickPosX = mouseClickedX - windowPosX
    local relativeClickPosY = mouseClickedY - windowPosY

    -- (Opzionale) Controlla se il click è all'interno della finestra
    local windowWidth, windowHeight = reaper.ImGui_GetWindowSize(ctx)
    if relativeClickPosX >= 0 and relativeClickPosX <= windowWidth and
       relativeClickPosY >= 0 and relativeClickPosY <= windowHeight then
        -- Il click è all'interno della finestra
        return relativeClickPosX, relativeClickPosY
    else
        -- Il click è fuori dalla finestra, puoi gestire questo caso come preferisci
        return relativeClickPosX, relativeClickPosY
    end
end

function validateWindowCoordinates(x, y)
    local mouseClickedX, mouseClickedY = x, y

    -- Ottieni la posizione dell'angolo in alto a sinistra della finestra ImGui
    local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola la posizione del click del mouse relativa alla finestra ImGui
    local relativeClickPosX = mouseClickedX - windowPosX
    local relativeClickPosY = mouseClickedY - windowPosY

    -- (Opzionale) Controlla se il click è all'interno della finestra
    local windowWidth, windowHeight = reaper.ImGui_GetWindowSize(ctx)
    if relativeClickPosX >= 0 and relativeClickPosX <= windowWidth and
       relativeClickPosY >= 0 and relativeClickPosY <= windowHeight then
        -- Il click è all'interno della finestra
        return true
    else
        -- Il click è fuori dalla finestra, puoi gestire questo caso come preferisci
        return false
    end
end

function onRightClick()
    if reaper.ImGui_IsMouseClicked(ctx, 1, false) and reaper.CountTracks(0) > 0 then
        -- Ottieni la posizione del click del mouse come coordinate assolute
        local absX, absY = GetMouseClickPositionInWindow(ctx, 1)

        if not absX or not absY then return end

        -- Converti le coordinate assolute in coordinate normalizzate
        local normalizedX = absX / ACTION_WINDOW_WIDTH
        local normalizedY = absY / ACTION_WINDOW_HEIGHT

        -- Crea un nuovo snapshot utilizzando le coordinate normalizzate
        snapshot_list[#snapshot_list + 1] = proj_snapshot:new(normalizedX, normalizedY)
        LAST_TOUCHED_BUTTON_INDEX = #snapshot_list

        --local ball_x, ball_y = windowToScreenCoordinates((normalizedX * ACTION_WINDOW_WIDTH - 1), (normalizedY * ACTION_WINDOW_HEIGHT - 3))

        local color = ball_default_color

        if INTERPOLATION_MODE == 0 then
            color = normalizeAlphaInRange(snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color,1,1)
        elseif INTERPOLATION_MODE == 1 then
            color = ball_default_color
        elseif INTERPOLATION_MODE == 2 then
            color = normalizeAlphaInRange(snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color,1,1)
        end

        for i, ball in ipairs(balls) do
            if INTERPOLATION_MODE == 0 then
                ball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
            elseif INTERPOLATION_MODE == 1 then
                ball.color = ball_default_color
            elseif INTERPOLATION_MODE == 2 then
                ball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
            end
        end
        
        table.insert(balls, { pos_x = normalizedX, pos_y = normalizedY, radius = 5, color = color, dragging = false })

        saveSelected()

        needToUpdateVoronoi = true
    end
end

function isMouseOverBall(ball_x, ball_y, radius)
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    return ((mouse_x - ball_x) ^ 2 + (mouse_y - ball_y) ^ 2) <= radius ^ 2
end

function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function checkIfBallsAreOverlapped(ball_1, ball_2, win_x, win_y, mouse_x_rel, mouse_y_rel, tolerance)

    local ball_1_pos_x = clamp(mouse_x_rel - ball_1.offset_x, 0.00001, 0.99999)
    local ball_1_pos_y = clamp(mouse_y_rel - ball_1.offset_y, 0.00001, 0.99999)

    local ball_1_screen_pos_x = win_x + ball_1_pos_x * ACTION_WINDOW_WIDTH
    local ball_1_screen_pos_y = win_y + ball_1_pos_y * ACTION_WINDOW_HEIGHT

    local ball_2_screen_pos_x = win_x + ball_2.pos_x * ACTION_WINDOW_WIDTH
    local ball_2_screen_pos_y = win_y + ball_2.pos_y * ACTION_WINDOW_HEIGHT

    local tolerance = tolerance or 5 -- Soglia di tolleranza in pixel

    -- Calcolo della distanza tra i centri delle due palle
    local dx = ball_1_screen_pos_x - ball_2_screen_pos_x
    local dy = ball_1_screen_pos_y - ball_2_screen_pos_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Calcolo del raggio totale più la soglia di tolleranza
    local total_radius_with_tolerance = ball_1.radius + ball_2.radius + tolerance
    
    -- Controllo dell'overlap
    if distance < total_radius_with_tolerance then
        return true
    else
        return false
    end
    
end

function round(numero)
    return numero >= 0 and math.floor(numero + 0.5) or math.ceil(numero - 0.5)
end

function decrementRGB(coloreU32, decremento)
    -- Estrai i componenti R, G, B, e A dal colore U32
    local a = (coloreU32 >> 24) & 0xFF
    local r = (coloreU32 >> 16) & 0xFF
    local g = (coloreU32 >> 8) & 0xFF
    local b = coloreU32 & 0xFF

    -- Decrementa i valori R, G, B di 30%
    r = round(math.max(0, r - r * decremento))
    g = round(math.max(0, g - g * decremento))
    b = round(math.max(0, b - b * decremento))

    -- Ricombina i componenti in un unico valore U32
    local nuovoColoreU32 = (a << 24) | (r << 16) | (g << 8) | b

    return nuovoColoreU32
end

function drawSnapshots()

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)

    for s, ball in ipairs(balls) do
        
        local ball_screen_pos_x = window_x + ball.pos_x * ACTION_WINDOW_WIDTH
        local ball_screen_pos_y = window_y + ball.pos_y * ACTION_WINDOW_HEIGHT

        reaper.ImGui_DrawList_AddCircle(draw_list, ball_screen_pos_x, ball_screen_pos_y, 6, ball.color, 4)
        if s == LAST_TOUCHED_BUTTON_INDEX then
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, ball_screen_pos_x, ball_screen_pos_y, 3, ball.color, 4)
        end

        if snapshot_list[s] then
            reaper.ImGui_SetNextItemWidth(ctx, 60)
            if ball.pos_x * ACTION_WINDOW_WIDTH > ((MAIN_WINDOW_WIDTH / 3) * 2) then
                local str_len = string.len(snapshot_list[s].name)
                local  w,  h = reaper.ImGui_CalcTextSize(ctx, snapshot_list[s].name, 60, 20)
                reaper.ImGui_SetCursorPos(ctx, ball.pos_x * ACTION_WINDOW_WIDTH - 12 - w, ball.pos_y * ACTION_WINDOW_HEIGHT - 10)
            else
                reaper.ImGui_SetCursorPos(ctx, ball.pos_x * ACTION_WINDOW_WIDTH + 12, ball.pos_y * ACTION_WINDOW_HEIGHT - 10)
            end

            reaper.ImGui_Text(ctx, snapshot_list[s].name)
        end

        
        if (isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) or DRAGGING_BALL) and isInterpolating == false then 
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
            ENABLE_WINDOW_RESIZE = false
        else
            ENABLE_WINDOW_RESIZE = true
        end
        
        -- DRAGGING
        if DRAGGING_BALL == ball or (isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) and not isInterpolating) then
            
            local mouse_x_rel = (mouse_x - window_x) / ACTION_WINDOW_WIDTH
            local mouse_y_rel = (mouse_y - window_y) / ACTION_WINDOW_HEIGHT

            if reaper.ImGui_IsMouseDown(ctx, 0) and not DRAGGING_BALL then

                for i, sball in ipairs(balls) do

                    if INTERPOLATION_MODE == 0 then
                        sball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
                    elseif INTERPOLATION_MODE == 1 then
                        sball.color = ball_default_color
                    elseif INTERPOLATION_MODE == 2 then
                        sball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
                    end
                    
                end

                    ball.color = decrementRGB(ball.color, 0.3)
                
                    
                DRAGGING_BALL = ball
                ball.clicked = true
                
                if mouse_x_rel >= 1 then mouse_x_rel = 0.99999 end
                if mouse_y_rel >= 1 then mouse_y_rel = 0.99999 end
            
                if mouse_x_rel <= 0 then mouse_x_rel = 0.00001 end
                if mouse_y_rel <= 0 then mouse_y_rel = 0.00001 end

                ball.offset_x, ball.offset_y = mouse_x_rel - ball.pos_x, mouse_y_rel - ball.pos_y
            end

            if reaper.ImGui_IsMouseDragging(ctx, 0, 0.2) and DRAGGING_BALL == ball then
                
                local ballsOverlapped = false

                for b, otherBall in ipairs(balls) do
                    if otherBall ~= ball then
                        if checkIfBallsAreOverlapped(ball, otherBall, window_x, window_y, mouse_x_rel, mouse_y_rel, 0) then
                            ballsOverlapped = true
                        end
                    end
                end

                if  ballsOverlapped == false then
                    ball.dragging = true
                    ball.pos_x = clamp(mouse_x_rel - ball.offset_x, 0.00001, 0.99999)
                    ball.pos_y = clamp(mouse_y_rel - ball.offset_y, 0.00001, 0.99999)
                    snapshot_list[s].x = ball.pos_x
                    snapshot_list[s].y = ball.pos_y
                    needToUpdateVoronoi = true
                else

                end

            end
        end

        -- MOUSE RELEASE
        if reaper.ImGui_IsMouseReleased(ctx, 0) and not isInterpolating and not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift())then
        
                if ball.dragging == false and ball.clicked == true then
                    if isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) then
                        LAST_TOUCHED_BUTTON_INDEX = s
        
                        for t = 1, #snapshot_list[s].track_list do
                            local track = getTrackByGUID(0, snapshot_list[s].track_list[t].guid)
        
                            for f = 1, #snapshot_list[s].track_list[t].fx_list do
                                --reaper.MB(snapshot_list[s].track_list[t].fx_list[f].guid, '', 0)
                                local retval, fx_index = getFxIndexByGUID(track, snapshot_list[s].track_list[t].fx_list[f].guid)
        
                                if retval then
                                    for p = 1, #snapshot_list[s].track_list[t].fx_list[f].param_list do
        
                                        local param_value = snapshot_list[s].track_list[t].fx_list[f].param_list[p]
                                        local param_index = snapshot_list[s].track_list[t].fx_list[f].param_index_list[p]
                                        
                                        if track then
        
                                            reaper.TrackFX_SetParam(track, fx_index, param_index, param_value)
        
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                ball.clicked = false
            --end

                ball.dragging = false
                DRAGGING_BALL = nil

                    for i, sball in ipairs(balls) do
                        if INTERPOLATION_MODE == 0 then
                            sball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
                        elseif INTERPOLATION_MODE == 1 then
                            sball.color = ball_default_color
                        elseif INTERPOLATION_MODE == 2 then
                            sball.color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
                        end
                    end

        end

        -- SHIFT-CLICK
        if reaper.ImGui_IsMouseClicked(ctx, 0) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) and isMouseOverBall(ball_screen_pos_x, ball_screen_pos_y, ball.radius) and not isInterpolating then
--[[             if LAST_TOUCHED_BUTTON_INDEX == s then 
                LAST_TOUCHED_BUTTON_INDEX = #snapshot_list - 1 
                reaper.ShowConsoleMsg('qui\n')
            end

            if LAST_TOUCHED_BUTTON_INDEX <= 0 then LAST_TOUCHED_BUTTON_INDEX = nil end ]]
            
            if LAST_TOUCHED_BUTTON_INDEX >= s then
                LAST_TOUCHED_BUTTON_INDEX = LAST_TOUCHED_BUTTON_INDEX - 1

                if LAST_TOUCHED_BUTTON_INDEX <= 0 then
                    LAST_TOUCHED_BUTTON_INDEX = nil
                    ENABLE_WINDOW_RESIZE = true
                end
            end 

            table.remove(snapshot_list, s)
            table.remove(balls, s)
            updateSnapshotIndexList()
            needToUpdateVoronoi = true
            break
        end
    end


    
end

function linearDistanceWeighting(points, x, y)
    local numerator = 0
    local denominator = 0

    for _, point in ipairs(points) do
        local dx = x - point.x
        local dy = y - point.y
        local distance = math.sqrt(dx^2 + dy^2)
        local maxDistance = snapshot_list[point.snapIndex].range * math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2)
        if distance <= maxDistance then -- Considera solo i punti entro maxDistance
            local weight = (maxDistance - distance) / maxDistance
            numerator = numerator + (point.value * weight)
            denominator = denominator + weight
        elseif distance == 0 then
            return point.value -- Ritorna immediatamente il valore se il punto è esattamente uguale
        end
        -- Ignora i punti con distanza maggiore di maxDistance
    end

    if denominator == 0 then return nil end -- Evita la divisione per zero
    return numerator / denominator
end

function inverseDistanceWeighting(points, x, y, power)
    local numerator = 0
    local denominator = 0
    power = power or 2 -- Imposta il valore di default del power se non specificato

    for _, point in ipairs(points) do
        local dx = x - point.x
        local dy = y - point.y
        local distance = math.sqrt(dx^2 + dy^2)
        if distance > 0 then -- Evita la divisione per zero
            local weight = 1 / (distance ^ power)
            numerator = numerator + (point.value * weight)
            denominator = denominator + weight
        else
            return point.value -- Ritorna immediatamente il valore se il punto è esattamente uguale
        end
    end

    if denominator == 0 then return 0 end -- Evita la divisione per zero
    return numerator / denominator
end

function containsValue(value, list)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

function gaussianKernel(distance, sigma)
    return math.exp(-((distance^2) / (2 * sigma^2)))
end

function calculateDynamicSigma(points, x, y)
    local distances = {}
    for _, point in ipairs(points) do
        local dx = x - point.x
        local dy = y - point.y
        table.insert(distances, math.sqrt(dx^2 + dy^2))
    end
    -- Calcola la media delle distanze come un esempio semplice di adattamento di sigma
    local sum = 0
    for _, distance in ipairs(distances) do
        sum = sum + distance
    end
    return sum / #distances
end

function smoothTransition(currentValue, targetValue, smoothingFactor)
    return currentValue + (targetValue - currentValue) * smoothingFactor
end

function naturalNeighborInterpolation(points, x, y, closestSnapshotsIndexes)
    local baseSigma = 80 -- Sigma di base
    local sigmaIncreaseFactor = 0.09 -- Fattore di aumento per sigma per unità di distanza

    local numerator = 0
    local denominator = 0

    for _, point in ipairs(points) do
        if containsValue(point.snapIndex, closestSnapshotsIndexes) then
            local dx = x - point.x
            local dy = y - point.y
            local distance = math.sqrt(dx^2 + dy^2)
            -- Aumenta sigma in base alla distanza
            local sigma = baseSigma + (sigmaIncreaseFactor * distance)
            local weight = gaussianKernel(distance, sigma)
            numerator = numerator + (point.value * weight)
            denominator = denominator + weight
        end
    end

    if denominator == 0 then return 0 end
    return numerator / denominator
end

function initSmoothing(x, y)
    CURRENT_DRAG_X, CURRENT_DRAG_Y = x, y -- Imposta le coordinate iniziali
    targetX, targetY = x, y -- Sincronizza il target con la posizione iniziale
    lastUpdateTime = reaper.time_precise()
    needToInitSmoothing = false
end

function updateSmoothingTarget(x, y)
    targetX, targetY = x, y -- Aggiorna il target con le nuove coordinate
end

function updateSmoothingPosition()
    local currentTime = reaper.time_precise()
    local deltaTime = currentTime - lastUpdateTime
    local smooth_multiplier

    if smoothing > 0 then smooth_multiplier = smoothing else smooth_multiplier = 0.3 end

    
    local smoothingFactor = deltaTime * smooth_multiplier -- Regola questo valore per modificare la "velocità" di smoothing

    CURRENT_DRAG_X = CURRENT_DRAG_X + (targetX - CURRENT_DRAG_X) * smoothingFactor
    CURRENT_DRAG_Y = CURRENT_DRAG_Y + (targetY - CURRENT_DRAG_Y) * smoothingFactor

    lastUpdateTime = currentTime
end

function windowToScreenCoordinates(xRelativo, yRelativo)
    -- Ottieni la posizione della finestra ImGui
    local posXFinestra, posYFinestra = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola le coordinate assolute aggiungendo le coordinate relative della finestra
    local xSchermo = posXFinestra + xRelativo
    local ySchermo = posYFinestra + yRelativo

    return xSchermo, ySchermo
end

function screenToWindowCoordinates(xSchermo, ySchermo)
    -- Ottieni la posizione della finestra ImGui
    local posXFinestra, posYFinestra = reaper.ImGui_GetWindowPos(ctx)

    -- Calcola le coordinate relative sottraendo la posizione della finestra dalle coordinate dello schermo
    local xRelativo = xSchermo - posXFinestra
    local yRelativo = ySchermo - posYFinestra

    return xRelativo, yRelativo
end

function onDragLeftMouse()
    
    if isInterpolating then
        if INTERPOLATION_MODE == 0 then
            onDragLeftMouseIDW()
        elseif INTERPOLATION_MODE == 1 then
            onDragLeftMouseNNI()
        elseif INTERPOLATION_MODE == 2 then
            onDragLeftMouseLDW()
        end
    else
        if  reaper.ImGui_GetMouseCursor(ctx) < 3 and
            reaper.ImGui_IsMouseDragging(ctx, 0) and
            validateWindowCoordinates(reaper.ImGui_GetMouseClickedPos(ctx, 0)) and
            #snapshot_list > 1 then
            --colorPickerWindowState == false then
            if INTERPOLATION_MODE == 0 then
                onDragLeftMouseIDW()
            elseif INTERPOLATION_MODE == 1 then
                onDragLeftMouseNNI()
            elseif INTERPOLATION_MODE == 2 then
                onDragLeftMouseLDW()
            end
        end
    end
end

function onDragLeftMouseNNI()
    
    if reaper.ImGui_IsMouseDragging(ctx, 0) and not DRAGGING_BALL and (LINK_TO_CONTROLLER == false or (LINK_TO_CONTROLLER == true and reaper.GetPlayState() == 0)) then
        isInterpolating = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = GetNormalizedMousePosition()

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
                previousInterpolatedValues = {}
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

        local temp_points = {}
        for k = 1, #snapshot_list do
            table.insert(temp_points, {x = snapshot_list[k].x * reaper.ImGui_GetWindowWidth(ctx), y = snapshot_list[k].y * reaper.ImGui_GetWindowHeight(ctx)})
        end

        local cpi = findClosestPointIndex(temp_points, {x = CURRENT_DRAG_X, y = CURRENT_DRAG_Y})
        local relatedPolyIndex = 0
        for i = 1, #snapshot_list do
            if snapIndexRelatedToPoly[i] == cpi then relatedPolyIndex = i end
        end

        local n = ivoronoi:getNeighborsForIndex(relatedPolyIndex)

        --reaper.ShowConsoleMsg('n: ' .. tostring(#n) .. '\n')

        local closest_snapshots = {}

        for l = 1, #n do
            table.insert(closest_snapshots, findClosestPointIndex(temp_points, n[l].centroid))
            --reaper.ShowConsoleMsg(tostring(findClosestPointIndex(temp_points, n[l].centroid)).. ' - ')
        end
        
        table.insert(closest_snapshots, cpi)
        

        local smoothingFactor = 0.6 -- Adegua questo valore in base alle tue necessità

        
        for groupIndex, group in ipairs(grouped_parameters) do
            local pointsForGroup = points_list[groupIndex]
            local interpolatedValue = naturalNeighborInterpolation(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y, closest_snapshots)
            -- Applica smoothing al valore interpolato
            if not previousInterpolatedValues[groupIndex] then
                previousInterpolatedValues[groupIndex] = interpolatedValue
            end
            local smoothedValue = smoothTransition(previousInterpolatedValues[groupIndex], interpolatedValue, smoothingFactor)
            previousInterpolatedValues[groupIndex] = smoothedValue -- Aggiorna il valore precedente con quello appena calcolato
            


            for _, parameter in ipairs(group) do
                reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, smoothedValue)
            end
        end

        for i = 1, #snapshot_list do
            if containsValue(i, closest_snapshots) then
                local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)
                drawDistanceLines(snap_x, snap_y, circle_x, circle_y, math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2))
            end
         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function onDragLeftMouseIDW()
    
    if reaper.ImGui_IsMouseDragging(ctx, 0) and not DRAGGING_BALL and (LINK_TO_CONTROLLER == false or (LINK_TO_CONTROLLER == true and reaper.GetPlayState() == 0)) then
        isInterpolating = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = GetNormalizedMousePosition()

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

         for groupIndex, group in ipairs(grouped_parameters) do
            --reaper.ShowConsoleMsg(tostring(points_list[groupIndex]) .. '\n')
            local pointsForGroup = points_list[groupIndex] -- Ottieni i punti corrispondenti per questo gruppo
        
            -- Calcola il valore interpolato per questo gruppo di punti
            local interpolatedValue = inverseDistanceWeighting(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y) -- power = 2 come esempio

            -- Applica questo valore interpolato a tutti i parametri nel gruppo
            if interpolatedValue then
                for _, parameter in ipairs(group) do
                    reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, interpolatedValue)
                end
            end
         end

         for i = 1, #snapshot_list do
            local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)
            drawDistanceLines(snap_x, snap_y, circle_x, circle_y, math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2), snapshot_list[i].color)
         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function onDragLeftMouseLDW()
    
    if reaper.ImGui_IsMouseDragging(ctx, 0) and not DRAGGING_BALL and (LINK_TO_CONTROLLER == false or (LINK_TO_CONTROLLER == true and reaper.GetPlayState() == 0)) then
        isInterpolating = true
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = GetNormalizedMousePosition()

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

         for groupIndex, group in ipairs(grouped_parameters) do
            --reaper.ShowConsoleMsg(tostring(points_list[groupIndex]) .. '\n')
            local pointsForGroup = points_list[groupIndex] -- Ottieni i punti corrispondenti per questo gruppo
        
            -- Calcola il valore interpolato per questo gruppo di punti
            local interpolatedValue = linearDistanceWeighting(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y) -- power = 2 come esempio

            -- Applica questo valore interpolato a tutti i parametri nel gruppo
            if interpolatedValue then
                for _, parameter in ipairs(group) do
                    reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, interpolatedValue)
                end
            end
         end

         for i = 1, #snapshot_list do
            local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)

            local range_in_pixel = snapshot_list[i].range * math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2)

            drawDistanceLines(snap_x, snap_y, circle_x, circle_y, range_in_pixel)

         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function drawDistanceLines(x1, y1, x2, y2, maxDistance, color)
    local color = color or reaper.ImGui_ColorConvertDouble4ToU32(1,1,1,1)
    local alpha =  inverselyProportionalValue(x1, y1, x2, y2, maxDistance) --+ 0.0000001
    color = normalizeAlphaInRange(color, alpha, alpha)
    drawLine(x1, y1, x2, y2, color, 3 * alpha)
end

function findClosestPointIndex(points, targetPoint)
    if #points == 0 then return nil end -- Controlla se la lista è vuota

    local closestIndex = 1 -- Inizializza l'indice del punto più vicino con il primo punto della lista
    local minDistance = ((points[closestIndex].x - targetPoint.x)^2 + (points[closestIndex].y - targetPoint.y)^2)

    for i = 2, #points do
        local point = points[i]
        local distance = ((point.x - targetPoint.x)^2 + (point.y - targetPoint.y)^2)
        if distance < minDistance then
            closestIndex = i
            minDistance = distance
        end
    end

    return closestIndex
end

function getControllerUpdateIDW() 

    if not DRAGGING_BALL then
        isInterpolating = true 
        --reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = 0, 0

        if reaper.ValidatePtr2(0, CONTROL_TRACK, 'MediaTrack*') == false then
            CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
            setControlTrackEnvelopeChunks(CONTROL_TRACK, CONTROL_FX_INDEX)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 0, 1)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 1, 1)
        end

        if  reaper.ImGui_GetMouseCursor(ctx) < 3 and
            reaper.ImGui_IsMouseDragging(ctx, 0) and
            canWriteControllerAutomation then

                if reaper.GetTrackAutomationMode(CONTROL_TRACK) == 1 then
                    reaper.SetTrackAutomationMode(CONTROL_TRACK, 4)
                end

                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())

            
        -- Ottieni la posizione normalizzata del mouse
                normalizedX, normalizedY = GetNormalizedMousePosition()
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0, normalizedX)
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1, normalizedY)
        else
            --local bilbo =  reaper.GetMediaTrackInfo_Value(CONTROL_TRACK, 'P_PROJECT')
            normalizedX, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0)
            normalizedY, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1)
            reaper.SetTrackAutomationMode(CONTROL_TRACK, 1)
        end

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

         for groupIndex, group in ipairs(grouped_parameters) do
            local pointsForGroup = points_list[groupIndex] -- Ottieni i punti corrispondenti per questo gruppo
            
            -- Calcola il valore interpolato per questo gruppo di punti
            local interpolatedValue = inverseDistanceWeighting(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y) -- power = 2 come esempio

            -- Applica questo valore interpolato a tutti i parametri nel gruppo
            if interpolatedValue then
                for _, parameter in ipairs(group) do
                    reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, interpolatedValue)
                end
            end
        end

        for i = 1, #snapshot_list do
            local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)
            drawDistanceLines(snap_x, snap_y, circle_x, circle_y, math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2), snapshot_list[i].color)
         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function getControllerUpdateLDW() 

    if not DRAGGING_BALL then
        isInterpolating = true 
        --reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = 0, 0

        if reaper.ValidatePtr2(0, CONTROL_TRACK, 'MediaTrack*') == false then
            CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
            setControlTrackEnvelopeChunks(CONTROL_TRACK, CONTROL_FX_INDEX)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 0, 1)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 1, 1)
        end

        if  reaper.ImGui_GetMouseCursor(ctx) < 3 and
            reaper.ImGui_IsMouseDragging(ctx, 0) and
            canWriteControllerAutomation then

                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())

                if reaper.GetTrackAutomationMode(CONTROL_TRACK) == 1 then
                    reaper.SetTrackAutomationMode(CONTROL_TRACK, 4)
                end
            
        -- Ottieni la posizione normalizzata del mouse
                normalizedX, normalizedY = GetNormalizedMousePosition()
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0, normalizedX)
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1, normalizedY)
        else
            --local bilbo =  reaper.GetMediaTrackInfo_Value(CONTROL_TRACK, 'P_PROJECT')
            normalizedX, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0)
            normalizedY, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1)
            reaper.SetTrackAutomationMode(CONTROL_TRACK, 1)
        end

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

         for groupIndex, group in ipairs(grouped_parameters) do
            local pointsForGroup = points_list[groupIndex] -- Ottieni i punti corrispondenti per questo gruppo
            
            -- Calcola il valore interpolato per questo gruppo di punti
            local interpolatedValue = linearDistanceWeighting(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y) -- power = 2 come esempio

            -- Applica questo valore interpolato a tutti i parametri nel gruppo
            if interpolatedValue then
                for _, parameter in ipairs(group) do
                    reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, interpolatedValue)
                end
            end
        end

        for i = 1, #snapshot_list do
            local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)

            local range_in_pixel = snapshot_list[i].range * math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2)

            drawDistanceLines(snap_x, snap_y, circle_x, circle_y, range_in_pixel)
         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function getControllerUpdateNNI() 

    if not DRAGGING_BALL then
        isInterpolating = true 
        --reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
        local normalizedX, normalizedY = 0, 0

        if reaper.ValidatePtr2(0, CONTROL_TRACK, 'MediaTrack*') == false then
            CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
            setControlTrackEnvelopeChunks(CONTROL_TRACK, CONTROL_FX_INDEX)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 0, 1)
            reaper.GetFXEnvelope(CONTROL_TRACK, CONTROL_FX_INDEX, 1, 1)
        end

        if  reaper.ImGui_GetMouseCursor(ctx) < 3 and
            reaper.ImGui_IsMouseDragging(ctx, 0) and
            canWriteControllerAutomation then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
        -- Ottieni la posizione normalizzata del mouse
            
            if reaper.GetTrackAutomationMode(CONTROL_TRACK) == 1 then
                reaper.SetTrackAutomationMode(CONTROL_TRACK, 4)
            end

                normalizedX, normalizedY = GetNormalizedMousePosition()
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0, normalizedX)
                reaper.TrackFX_SetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1, normalizedY)
        else
            --local bilbo =  reaper.GetMediaTrackInfo_Value(CONTROL_TRACK, 'P_PROJECT')
            
            normalizedX, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 0)
            normalizedY, min, max = reaper.TrackFX_GetParam(CONTROL_TRACK, CONTROL_FX_INDEX, 1)
        end

        -- Converti le coordinate normalizzate in posizione reale se necessario
        -- Esempio: applicazione diretta senza conversione, poiché la logica IDW utilizza valori normalizzati
        DRAG_X = normalizedX * ACTION_WINDOW_WIDTH
        DRAG_Y = normalizedY * ACTION_WINDOW_HEIGHT

        if smoothing_fader_value ~= 0 then
            if needToInitSmoothing == true then
                initSmoothing(DRAG_X, DRAG_Y)
                updateSnapshotIndexList()
                previousInterpolatedValues = {}
            end

            updateSmoothingTarget(DRAG_X, DRAG_Y)
            updateSmoothingPosition()
        else
            CURRENT_DRAG_X = DRAG_X
            CURRENT_DRAG_Y = DRAG_Y
        end

        CURRENT_DRAG_X = clamp(CURRENT_DRAG_X, 0, ACTION_WINDOW_WIDTH)
        CURRENT_DRAG_Y = clamp(CURRENT_DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        DRAG_X = clamp(DRAG_X, 0, ACTION_WINDOW_WIDTH)
        DRAG_Y = clamp(DRAG_Y, 0, ACTION_WINDOW_HEIGHT)

        local circle_x, circle_y = windowToScreenCoordinates(CURRENT_DRAG_X, CURRENT_DRAG_Y)
        local dot_x, dot_y = windowToScreenCoordinates(DRAG_X, DRAG_Y)

        drawCircle(circle_x,circle_y, 10, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)
        drawDot(dot_x,dot_y, 3, reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 4)

        local temp_points = {}
        for k = 1, #snapshot_list do
            table.insert(temp_points, {x = snapshot_list[k].x * reaper.ImGui_GetWindowWidth(ctx), y = snapshot_list[k].y * reaper.ImGui_GetWindowHeight(ctx)})
        end

        local cpi = findClosestPointIndex(temp_points, {x = CURRENT_DRAG_X, y = CURRENT_DRAG_Y})
        local relatedPolyIndex = 0
        for i = 1, #snapshot_list do
            if snapIndexRelatedToPoly[i] == cpi then relatedPolyIndex = i end
        end

        local n = ivoronoi:getNeighborsForIndex(relatedPolyIndex)

        --reaper.ShowConsoleMsg('n: ' .. tostring(#n) .. '\n')

        local closest_snapshots = {}

        for l = 1, #n do
            table.insert(closest_snapshots, findClosestPointIndex(temp_points, n[l].centroid))
            --reaper.ShowConsoleMsg(tostring(findClosestPointIndex(temp_points, n[l].centroid)).. ' - ')
        end
        
        table.insert(closest_snapshots, cpi)
        

        local smoothingFactor = 0.6 -- Adegua questo valore in base alle tue necessità

        
        for groupIndex, group in ipairs(grouped_parameters) do
            local pointsForGroup = points_list[groupIndex]
            local interpolatedValue = naturalNeighborInterpolation(pointsForGroup, CURRENT_DRAG_X, CURRENT_DRAG_Y, closest_snapshots)
            -- Applica smoothing al valore interpolato
            if not previousInterpolatedValues[groupIndex] then
                previousInterpolatedValues[groupIndex] = interpolatedValue
            end
            local smoothedValue = smoothTransition(previousInterpolatedValues[groupIndex], interpolatedValue, smoothingFactor)
            previousInterpolatedValues[groupIndex] = smoothedValue -- Aggiorna il valore precedente con quello appena calcolato

            for _, parameter in ipairs(group) do
                reaper.TrackFX_SetParam(parameter.track, parameter.fx_index, parameter.param_list_index, smoothedValue)
            end
        end

        for i = 1, #snapshot_list do
            if containsValue(i, closest_snapshots) then
                local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)
                drawDistanceLines(snap_x, snap_y, circle_x, circle_y, math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2))
            end
         end

    else
        isInterpolating = false
        needToInitSmoothing = true
    end
end

function inverselyProportionalValue(x1, y1, x2, y2, maxDistance)
    -- Calcola la distanza euclidea tra i due punti
    local distance = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)

    -- Verifica per evitare divisione per zero o risultati non validi
    if distance == 0 then
        return 1 -- I punti sono coincidenti, valore massimo
    elseif distance >= maxDistance then
        return 0 -- La distanza è uguale o superiore a maxDistance, valore minimo
    else
        -- Calcola il valore inversamente proporzionale
        return 1 - (distance / maxDistance)
    end
end

function exponentiallyProportionalValue(x1, y1, x2, y2, maxDistance, exponent)
    -- Calcola la distanza euclidea tra i due punti
    local exponent = exponent or 2
    local distance = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)

    -- Verifica per evitare divisione per zero o risultati non validi
    if distance == 0 then
        return 1 -- I punti sono coincidenti, valore massimo
    elseif distance >= maxDistance then
        return 0 -- La distanza è uguale o superiore a maxDistance, valore minimo
    else
        -- Calcola il valore esponenzialmente proporzionale
        return math.exp(-distance / maxDistance * exponent)
    end
end

function logarithmicallyProportionalValue(x1, y1, x2, y2, maxDistance, base, offset)
    -- Calcola la distanza euclidea tra i due punti
    local base = base or 2
    local offset = offset or 200
    local distance = math.sqrt((x2 - x1)^2 + (y2 - y1)^2) + offset

    -- Verifica per evitare divisione per zero o risultati non validi
    if distance - offset == 0 then
        return 1 -- I punti sono coincidenti, valore massimo
    elseif distance - offset >= maxDistance then
        return 0 -- La distanza è uguale o superiore a maxDistance, valore minimo
    else
        -- Calcola il valore logaritmicamente proporzionale
        -- Assicurati che la base del logaritmo sia maggiore di 1 per un decremento positivo
        local adjustedMaxDistance = math.log(maxDistance + offset, base)
        local value = math.log(distance, base) / adjustedMaxDistance
        return 1 - value
    end
end

function isUserMovingWindow(ctx)
    -- Ottiene la posizione corrente della finestra
    local currentWindowPosX, currentWindowPosY = reaper.ImGui_GetWindowPos(ctx)

    -- Inizializza lastWindowPosX e lastWindowPosY al primo ciclo
    if lastWindowPosX == nil or lastWindowPosY == nil then
        lastWindowPosX, lastWindowPosY = currentWindowPosX, currentWindowPosY
        return false
    end

    -- Verifica se la posizione della finestra è cambiata dall'ultimo frame
    local isMoving = currentWindowPosX ~= lastWindowPosX or currentWindowPosY ~= lastWindowPosY

    -- Aggiorna lastWindowPosX e lastWindowPosY per il prossimo ciclo
    lastWindowPosX, lastWindowPosY = currentWindowPosX, currentWindowPosY

    return isMoving
end

function getControllerUpdate()

    if reaper.ImGui_IsMouseDragging(ctx, 0) then
        if reaper.GetTrackAutomationMode(CONTROL_TRACK) == 1 then
            reaper.SetTrackAutomationMode(CONTROL_TRACK, 4)
        end
    else
        reaper.SetTrackAutomationMode(CONTROL_TRACK, 1)
    end

    if INTERPOLATION_MODE == 0 then
        getControllerUpdateIDW()
    elseif INTERPOLATION_MODE == 1 then
        getControllerUpdateNNI()
    elseif INTERPOLATION_MODE == 2 then
        getControllerUpdateLDW()
    end
end

function updateSnapshotIndexList()

    if #snapshot_list <= 1 then
        grouped_parameters = {}
        points_list = {}
        return
    end

    local parameters_to_be_updated = {}

    for s1 = 1, #snapshot_list do
        for s2 = 1, #snapshot_list do
            
            for t = 1, #snapshot_list[s1].track_list do
                local retval, track_list_index = checkIfSameTrackExists(snapshot_list[s1].track_list[t], snapshot_list[s2].track_list)
                
                if retval then
                    local track = getTrackByGUID(0, snapshot_list[s1].track_list[t].guid)

                    for f = 1, #snapshot_list[s1].track_list[t].fx_list do
                        local retval, fx_list_index = checkIfSameFxExists(snapshot_list[s1].track_list[t].fx_list[f], snapshot_list[s2].track_list[track_list_index].fx_list)
                            
                        if retval then
                            local retval, fx_parameter_indexes = checkIfParametersHaveDifferentValues(snapshot_list[s1].track_list[t].fx_list[f].param_list, snapshot_list[s2].track_list[track_list_index].fx_list[fx_list_index].param_list)
                            
                            if retval then
                                for p = 1, #fx_parameter_indexes do

                                    if track then
                                        local retval, track_name = reaper.GetTrackName(track)
                                        local fx_index_retval, fx = getFxIndexByGUID(track, snapshot_list[s1].track_list[t].fx_list[f].guid)

                                        if fx_index_retval then

                                            local retval, fx_name = reaper.TrackFX_GetFXName(track, fx)
                                            local retval, param_name = reaper.TrackFX_GetParamName(track, fx, fx_parameter_indexes[p] - 1)

                                            if  not containsAnyFormOf(track_name, IGNORE_TRACKS_POST_SAVE_STRING) and
                                                not containsAnyFormOf(fx_name, IGNORE_FXs_POST_SAVE_STRING) and
                                                not containsAnyFormOf(param_name, IGNORE_PARAMS_POST_SAVE_STRING) then
 
                                                local parameter_index = fx_parameter_indexes[p]
                                                local new_parameter = parameter:new(track, fx, snapshot_list[s1].track_list[t].fx_list[f].param_index_list[parameter_index], snapshot_list[s1].track_list[t].fx_list[f].param_list[parameter_index], s1)
                                                table.insert(parameters_to_be_updated, new_parameter)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end


    grouped_parameters = {} -- Questo conterrà le liste finali raggruppate

    for _, parameter in ipairs(parameters_to_be_updated) do
        local foundGroup = false

        for _, group in ipairs(grouped_parameters) do
            if  group[1].track == parameter.track and
                group[1].fx_index == parameter.fx_index and
                group[1].param_list_index == parameter.param_list_index then
                table.insert(group, parameter)
                foundGroup = true
                break
            end
        end

        if not foundGroup then
            table.insert(grouped_parameters, {parameter})
        end
    end

    points_list = {}

    for _, group in ipairs(grouped_parameters) do
        local pointsForGroup = {} -- Lista di punti per l'attuale gruppo di parametri
    
        for _, param in ipairs(group) do
            local snap = snapshot_list[param.snap_index] -- Ottieni lo snapshot basato sull'indice
    
            if snap then -- Controlla se lo snapshot esiste per evitare errori
                local point = {
                    x = snap.x * ACTION_WINDOW_WIDTH,
                    y = snap.y * ACTION_WINDOW_HEIGHT,
                    value = param.param_value,
                    snapIndex = param.snap_index
                }
                table.insert(pointsForGroup, point)
            end
        end
    
        -- Aggiungi i punti generati per questo gruppo alla lista principale dei punti
        table.insert(points_list, pointsForGroup)
    end

end

function saveSelected()
    
    if LAST_TOUCHED_BUTTON_INDEX and reaper.CountTracks(0) > 0 then

        local s = LAST_TOUCHED_BUTTON_INDEX

        local temp_x = snapshot_list[s].x
        local temp_y = snapshot_list[s].y

        local snap_name = snapshot_list[s].name or ('Snap ' .. tostring(s))

        if snapshot_list[s] then
            snapshot_list[s] = proj_snapshot:new(temp_x, temp_y, snap_name, snapshot_list[s].color, snapshot_list[s].range)
        else
            snapshot_list[s] = proj_snapshot:new(temp_x, temp_y, snap_name)
        end

        if INTERPOLATION_MODE == 0 then
            balls[s].color = normalizeAlphaInRange(snapshot_list[s].color,1,1)
        elseif INTERPOLATION_MODE == 1 then
            balls[s].color = reaper.ImGui_ColorConvertDouble4ToU32(1,1,1,1)
        elseif INTERPOLATION_MODE == 2 then  
            balls[s].color = normalizeAlphaInRange(snapshot_list[s].color,1,1)
        end

        for i = 0, reaper.CountTracks(0) - 1 do
            local current_track = reaper.GetTrack(0,i)
            local new_track_snapshot = track_snapshot:new(reaper.GetTrackGUID(current_track))
            table.insert(snapshot_list[s].track_list, new_track_snapshot)
            --snapshot_list[s].track_list[#snapshot_list[s].track_list + 1] = new_track_snapshot

            for j = 0, reaper.TrackFX_GetCount(current_track) - 1 do
                local current_fx_index_retval, current_fx_index = getFxIndexByGUID(current_track, reaper.TrackFX_GetFXGUID(current_track, j))
                local new_fx_snapshot = fx_snapshot:new(reaper.TrackFX_GetFXGUID(current_track, j))
                table.insert(snapshot_list[s].track_list[i+1].fx_list, new_fx_snapshot)

                for z = 0, reaper.TrackFX_GetNumParams(current_track, current_fx_index) - 1 do
                    local retval, p_name = reaper.TrackFX_GetParamName(current_track, current_fx_index, z)
                    local retval, t_name = reaper.GetTrackName(current_track)
                    local retval, fx_name = reaper.TrackFX_GetFXName(current_track, current_fx_index)

                    if  not containsAnyFormOf(p_name, IGNORE_PARAMS_PRE_SAVE_STRING .. ', mtt_mc_') and
                        not containsAnyFormOf(t_name, IGNORE_TRACKS_PRE_SAVE_STRING) and
                        not containsAnyFormOf(fx_name, IGNORE_FXs_PRE_SAVE_STRING) then
                    
                        local retval, minval, maxval
                        retval, minval, maxval = reaper.TrackFX_GetParam(current_track, current_fx_index, z)
                        table.insert(snapshot_list[s].track_list[i+1].fx_list[j+1].param_list, retval)
                        table.insert(snapshot_list[s].track_list[i+1].fx_list[j+1].param_index_list, z)
                    end
                end
            end
        end

        snapshot_list[s].assigned = true

        updateSnapshotIndexList()
    end

    reaper.MarkProjectDirty(0)

    PROJECT_PATH = reaper.GetProjectPath(0)
end

function checkIfParametersHaveDifferentValues(param_list_1, param_list_2)

    local param_list_indexes = {}
    local retval = false

    for i = 1, #param_list_1 do
        if param_list_1[i] ~= param_list_2[i] then
            table.insert(param_list_indexes, i)
            retval = true
        end
    end

    if retval then
        return true, param_list_indexes
    else
        return false, nil
    end

end

function checkIfSameTrackExists(track, track_list)

    for i = 1, #track_list do
        if track.guid == track_list[i].guid then
            return true, i
        end
    end

    return false, nil
end

function checkIfSameFxExists(fx, fx_list)

    for i = 1, #fx_list do
        if fx.guid == fx_list[i].guid then
            return true, i
        end
    end

    return false, nil
end

function containsAnyFormOf(s, ref_string)

    if not ref_string then return false end

    -- Prepara s rimuovendo gli spazi superflui e convertendola in minuscolo
    local compactS = s:gsub("%s+", ""):lower()

    -- Divide ref_string in base alle virgole, gestendo spazi
    for segment in ref_string:gmatch("[^,]+") do
        -- Rimuove gli spazi all'inizio e alla fine di ogni segmento e controlla per corrispondenze esatte o generiche
        local word = segment:match("^%s*(.-)%s*$")
        local exactMatch = word:match('^"(.*)"$')
        
        if exactMatch then
            -- Se la parola chiave è tra virgolette, cerca corrispondenza esatta in s senza rimuovere gli spazi e convertendo in minuscolo
            if s:lower() == exactMatch:lower() then
                return true
            end
        else
            -- Altrimenti, cerca la parola chiave in qualsiasi punto della stringa compactS
            if string.find(compactS, word:lower()) then
                return true
            end
        end
    end

    return false
end

function mainWindow()

    --reaper.ImGui_Text(ctx, tostring(reaper.ImGui_GetFramerate(ctx)))

    if reaper.ImGui_ImageButton(ctx, 'Save Selected', save_icon, 20, 20 ) then
        saveSelected()
    end

    reaper.ImGui_SameLine(ctx)

    
    if reaper.ImGui_ImageButton(ctx, 'Clear', bin_icon, 20, 20 ) then
        for k in pairs (snapshot_list) do
            snapshot_list = {}
            grouped_parameters = {}
            points_list = {}
            balls = {}
        end

        LAST_TOUCHED_BUTTON_INDEX = nil
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 2)
    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 3)
    reaper.ImGui_Text(ctx, 'Smooth:')
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 40)
    local retval = false
    retval, smoothing_fader_value = reaper.ImGui_DragDouble(ctx, '##SmoothingValue', smoothing_fader_value, 0.01, 0, 1, '%.2f', reaper.ImGui_SliderFlags_AlwaysClamp())
    smoothing = (1 - smoothing_fader_value) * smoothing_max_value
    
    if snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 2)
        --reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 3)
        reaper.ImGui_Text(ctx, 'Range:')
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 40)
        local retval = false

        retval, range_fader_value = reaper.ImGui_DragDouble(ctx, '##Range', snapshot_list[LAST_TOUCHED_BUTTON_INDEX].range, 0.01, 0, 1, '%.2f', reaper.ImGui_SliderFlags_AlwaysClamp())
        if retval then
            snapshot_list[LAST_TOUCHED_BUTTON_INDEX].range = range_fader_value
        end
    else
        --retval, range_fader_value = reaper.ImGui_DragDouble(ctx, '##RangeFake', range_fader_value, 0.01, 0, 1, '%.2f', reaper.ImGui_SliderFlags_AlwaysClamp())
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 60)
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 5)

    if snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then

        --reaper.ImGui_SameLine(ctx)

        --reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 35 - 35 - 33)            
                        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].color)

        local retval = reaper.ImGui_Button(ctx, '##selected_snap_color', 25, 25 )

        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopStyleColor(ctx)

        if retval then
            colorPickerWindowState = not colorPickerWindowState
        end

    else
        colorPickerWindowState = false
    end

    local textEditWidth = MAIN_WINDOW_WIDTH - 35 - 60 - 110 - 110 - 85 -- 100

    if LAST_TOUCHED_BUTTON_INDEX and snapshot_list[LAST_TOUCHED_BUTTON_INDEX] then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, textEditWidth)
        local rv
        rv, snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name = reaper.ImGui_InputText(ctx, '##ti'.. tostring(LAST_TOUCHED_BUTTON_INDEX), snapshot_list[LAST_TOUCHED_BUTTON_INDEX].name, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

        if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
            is_name_edited = false
        end

        if reaper.ImGui_IsItemActivated(ctx) then
            is_name_edited = true
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 10)
    else
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + textEditWidth + 18)
    end
    
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 35)

    if reaper.ImGui_ImageButton(ctx, 'Preferences', cog_icon, 20, 20 ) then
        preferencesWindowState = not preferencesWindowState
    end

    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetWindowWidth(ctx) - 35 - 35)

    local link_button_retval = false

    if LINK_TO_CONTROLLER == true then
        link_button_retval = reaper.ImGui_ImageButton(ctx, 'Link to Controller', link_icon, 20, 20, nil, nil, nil, nil, nil, nil)
    else
        link_button_retval = reaper.ImGui_ImageButton(ctx, 'Link to Controller', link_icon, 20, 20, nil, nil, nil, nil, nil, reaper.ImGui_ColorConvertDouble4ToU32(0.5,0.5,0.5,0.5))
    end

    if link_button_retval then
        
        reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
        local ctrlDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl())
        local shiftDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift())

        local controlTrack, fx_index = getControlTrack()

        if shiftDown then
            --boolean reaper.SetEnvelopeStateChunk(TrackEnvelope env, string str, boolean isundo)
            local envelope = reaper.GetFXEnvelope(controlTrack, fx_index, 0, 0)
            reaper.DeleteEnvelopePointRange(envelope, -math.huge, math.huge)
            
            reaper.SetEnvelopePoint(envelope, 0, 0, 0.5)

            local envelope = reaper.GetFXEnvelope(controlTrack, fx_index, 1, 0)
            reaper.DeleteEnvelopePointRange(envelope, -math.huge, math.huge)

            reaper.SetEnvelopePoint(envelope, 0, 0, 0.5)

            reaper.TrackFX_SetParam(controlTrack, fx_index, 0, 0.5)
            reaper.TrackFX_SetParam(controlTrack, fx_index, 1, 0.5)

            reaper.UpdateArrange()

            

        end

        if ctrlDown then
            if reaper.GetMediaTrackInfo_Value(controlTrack, "B_SHOWINTCP") == 0 then
                setControlTrackVisibility(controlTrack, true)
            else
                setControlTrackVisibility(controlTrack, false)
            end

            reaper.TrackList_AdjustWindows(false)

        end

        if (not shiftDown) and (not ctrlDown) then 
            LINK_TO_CONTROLLER = not LINK_TO_CONTROLLER
        end
        
    end

    

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 0)
    reaper.ImGui_SetCursorPosX(ctx, WIDTH_OFFSET * 0.5)

    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 2))

    reaper.ImGui_BeginChildFrame(ctx, 'MovementWindow', ACTION_WINDOW_WIDTH, ACTION_WINDOW_HEIGHT,   reaper.ImGui_WindowFlags_NoMove()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollbar()
                                                                                                    | reaper.ImGui_WindowFlags_NoScrollWithMouse()
                                                                                                    | reaper.ImGui_WindowFlags_TopMost()
                                                                                                    | reaper.ImGui_WindowFlags_AlwaysUseWindowPadding()
                                                                                                    | reaper.ImGui_WindowFlags_NoResize())
                                                                        
    reaper.ImGui_PopStyleVar(ctx)

    if reaper.ImGui_IsMouseClicked(ctx, 0) then
        local MOUSE_CLICKED_POSITION_X, MOUSE_CLICKED_POSITION_Y = reaper.ImGui_GetMouseClickedPos(ctx, 0)
        if validateWindowCoordinates(MOUSE_CLICKED_POSITION_X, MOUSE_CLICKED_POSITION_Y) then
            canWriteControllerAutomation = true
        end
    end

    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        canWriteControllerAutomation = false
    end
        

    if INTERPOLATION_MODE == 0 then
        local x,y = reaper.ImGui_GetWindowPos(ctx)
        reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx), x, y, x + ACTION_WINDOW_WIDTH, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.085,0.085,0.085,1))
        reaper.ImGui_DrawList_AddRect(reaper.ImGui_GetWindowDrawList(ctx), x + 3, y, x + ACTION_WINDOW_WIDTH - 1, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.2,0.2,1))
    elseif INTERPOLATION_MODE == 1 then
        local x,y = reaper.ImGui_GetWindowPos(ctx)
        reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx), x, y, x + ACTION_WINDOW_WIDTH, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.085,0.085,0.085,1))
        drawVoronoi()
        reaper.ImGui_DrawList_AddRect(reaper.ImGui_GetWindowDrawList(ctx), x + 3, y, x + ACTION_WINDOW_WIDTH - 1, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.2,0.2,1))
    elseif INTERPOLATION_MODE == 2 then
        local x,y = reaper.ImGui_GetWindowPos(ctx)
        if #snapshot_list >= 1 then
            
            reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx), x, y, x + ACTION_WINDOW_WIDTH, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,1))
            drawSpheres()
        else
            reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx), x, y, x + ACTION_WINDOW_WIDTH, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.085,0.085,0.085,1))
        end
            reaper.ImGui_DrawList_AddRect(reaper.ImGui_GetWindowDrawList(ctx), x + 3, y, x + ACTION_WINDOW_WIDTH - 1, y + ACTION_WINDOW_HEIGHT, reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.2,0.2,1))
        
    end

    if not isInterpolating and not isInfoStringHovered then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(2, 2, 2, 0.9))
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 0.1))
    end

    reaper.ImGui_PushFont(ctx, comic_sans_smaller)
    reaper.ImGui_SetCursorPosY(ctx, ACTION_WINDOW_HEIGHT - 125)
    reaper.ImGui_SetCursorPosX(ctx, 9)
    reaper.ImGui_Text(ctx, "Right-Click: make a snapshot of current FXs\nLeft-Drag on Snapshot: move\nShift + Left-Click on Snapshot: remove\nLeft-Click on Snapshot: select and load FXs values\nMouse-Wheel on Snapshot: adjust range\nCtrl + Mouse-Wheel: adjust Smooth\nLeft-Drag: interpolate")
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    
    local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
    local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)

    if IsAnyPointInsideRect(snapshot_list, {x1, y1, x2, y2})then
        isInfoStringHovered = true
    else
        isInfoStringHovered = false
    end 

    onRightClick()
    drawSnapshots()

    if LINK_TO_CONTROLLER == false then
        onDragLeftMouse()
    end

    if LINK_TO_CONTROLLER == true then
        if reaper.GetPlayState() == 1 then
            if PLAY_STATE == false then
                CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
                setControlTrackEnvelopeChunks(CONTROL_TRACK, CONTROL_FX_INDEX)
                needToInitSmoothing = true
                updateSnapshotIndexList()
                PLAY_STATE = true
            end

            getControllerUpdate()

        end

        if reaper.GetPlayState() == 0 then
            if PLAY_STATE == true then
                PLAY_STATE = false
                isInterpolating = false
            end
        end
        
    end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) and is_name_edited == false then

        if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) then
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_LOOP_COMMAND), 0)
        else
            reaper.Main_OnCommand(reaper.NamedCommandLookup(PLAY_STOP_COMMAND), 0)
        end
    end
    
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftSuper()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_S()) then
        reaper.Main_OnCommand(reaper.NamedCommandLookup(SAVE_PROJECT_COMMAND), 0)
    end

    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftSuper()) and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_W()) then
        quit = true
    end
    
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)

    local hoveringSnapshot = false

    for i = 1, #snapshot_list do
        local snap_x, snap_y = windowToScreenCoordinates(snapshot_list[i].x * reaper.ImGui_GetWindowWidth(ctx), snapshot_list[i].y * reaper.ImGui_GetWindowHeight(ctx))
        
        if checkIfPointsAreaOverlapped(mouse_x, mouse_y, snap_x, snap_y, 6) and not reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) then
            if reaper.ImGui_GetMouseWheel(ctx) > 0 and snapshot_list[i].range < 1 then
                snapshot_list[i].range = snapshot_list[i].range + 0.02 
            elseif reaper.ImGui_GetMouseWheel(ctx) < 0 and snapshot_list[i].range >= 0 then
                snapshot_list[i].range = snapshot_list[i].range - 0.02
                if snapshot_list[i].range < 0.01 then snapshot_list[i].range = 0 end
            end

            hoveringSnapshot = true
        end    
    end

    --reaper.ShowConsoleMsg(tostring(reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift())))

    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) and not hoveringSnapshot then
        if reaper.ImGui_GetMouseWheel(ctx) > 0 and smoothing_fader_value < 1 then
            smoothing_fader_value = smoothing_fader_value + 0.02
        elseif reaper.ImGui_GetMouseWheel(ctx) < 0 and smoothing_fader_value >= 0 then
            smoothing_fader_value = smoothing_fader_value - 0.02
            if smoothing_fader_value < 0.01 then smoothing_fader_value = 0 end
        end
    end

    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_EndChild(ctx)
    
end

function checkIfPointsAreaOverlapped(x1, y1, x2, y2, pixelTolerance)

        -- Calcola la distanza tra il mouse e il punto di riferimento
        local deltaX = x2 - x1
        local deltaY = y2 - y1
        local distanzaDalPunto = math.sqrt(deltaX^2 + deltaY^2)
    
        -- Verifica se il mouse è all'interno del range specificato
        return distanzaDalPunto <= pixelTolerance
end

function IsAnyPointInsideRect(points, rect)
    -- points: lista di punti dove ogni punto è un table {x, y}
    -- rect: un table che rappresenta il rettangolo con {x1, y1, x2, y2},
    -- dove (x1, y1) sono le coordinate dell'angolo superiore sinistro,
    -- e (x2, y2) quelle dell'angolo inferiore destro del rettangolo.
    --reaper.ShowConsoleMsg(#rect)
    for _, point in ipairs(points) do
        local x, y = windowToScreenCoordinates(point.x * ACTION_WINDOW_WIDTH, point.y * ACTION_WINDOW_HEIGHT)
        if x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4] then
            return true -- Almeno un punto è dentro al rettangolo
        end
    end
    
    return false -- Nessun punto è dentro al rettangolo
end

function IsMouseStillForXSeconds(ctx, threshold)
    -- Ottiene la posizione corrente del mouse
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)

    -- Controlla se la posizione del mouse è cambiata
    if mouseX ~= lastMousePosX or mouseY ~= lastMousePosY then
        -- Aggiorna l'ultima posizione del mouse e il tempo
        lastMousePosX, lastMousePosY = mouseX, mouseY
        lastTimeMouseMoved = reaper.time_precise()
    end

    -- Calcola la differenza di tempo da quando il mouse si è mosso l'ultima volta
    local timeSinceLastMove = reaper.time_precise() - lastTimeMouseMoved

    -- Controlla se il tempo da quando il mouse si è mosso l'ultima volta è maggiore del threshold
    return timeSinceLastMove >= threshold
end

function whichPointIsInThisPolygon(puntiPoligono, listaPunti) -- :)
    local function puntoInterno(x, y, xp, yp)
        local npol = #xp
        local j = npol
        local c = false
        for i = 1, npol do
            if (((yp[i] <= y) and (y < yp[j])) or ((yp[j] <= y) and (y < yp[i]))) and
               (x < (xp[j] - xp[i]) * (y - yp[i]) / (yp[j] - yp[i]) + xp[i]) then
                c = not c
            end
            j = i
        end
        return c
    end

    local xp = {}
    local yp = {}
    for i = 1, #puntiPoligono, 2 do
        table.insert(xp, puntiPoligono[i])
        table.insert(yp, puntiPoligono[i+1])
    end

    for i, punto in ipairs(listaPunti) do
        if puntoInterno(punto.x, punto.y, xp, yp) then
            return i -- Restituisce l'indice del primo punto interno
        end
    end

    return nil -- Nessun punto trovato all'interno del poligono
end

function drawVoronoi()
    
    if #snapshot_list > 1 then

        if needToUpdateVoronoi then

            snapPointsForVoronoi = {}

            snapIndexRelatedToPoly = {}

            for i = 1, #snapshot_list do
                table.insert(snapPointsForVoronoi, {x = snapshot_list[i].x * reaper.ImGui_GetWindowWidth(ctx), y = snapshot_list[i].y * reaper.ImGui_GetWindowHeight(ctx)})
            end

            ivoronoi = voronoilib:new(#snapshot_list,snapPointsForVoronoi,1,0,0,reaper.ImGui_GetWindowWidth(ctx),reaper.ImGui_GetWindowHeight(ctx))
            
        end

        for v = 1, #ivoronoi.polygons do
            local verts_line = {}

            for g = 1, #ivoronoi.polygons[v].points do
                table.insert(verts_line, ivoronoi.polygons[v].points[g])
            end

            local polygon_verts = {}

            for i = 1, #verts_line, 2 do
                local x, y = windowToScreenCoordinates(verts_line[i], verts_line[i+1])
                table.insert(polygon_verts, x)
                table.insert(polygon_verts, y)
            end

            local snapIndex = whichPointIsInThisPolygon(verts_line,snapPointsForVoronoi) or v
           
            reaper.ImGui_DrawList_AddConvexPolyFilled(reaper.ImGui_GetWindowDrawList(ctx), reaper.new_array(polygon_verts, #polygon_verts), snapshot_list[snapIndex].color)
        
            for index,segment in pairs(ivoronoi.segments) do
                local x1, y1 = windowToScreenCoordinates(segment.startPoint.x,segment.startPoint.y)
                local x2, y2 = windowToScreenCoordinates(segment.endPoint.x,segment.endPoint.y)
                drawLine(x1,y1,x2,y2, reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 1), 1)
            end

            table.insert(snapIndexRelatedToPoly, snapIndex)
        end

        needToUpdateVoronoi = false
    else
        if #snapshot_list == 1 then

            local polygon_verts = {}

            local x, y = windowToScreenCoordinates(0, 0)
            table.insert(polygon_verts, x)
            table.insert(polygon_verts, y)

            x, y = windowToScreenCoordinates(reaper.ImGui_GetWindowWidth(ctx), 0)
            table.insert(polygon_verts, x)
            table.insert(polygon_verts, y)

            x, y = windowToScreenCoordinates(reaper.ImGui_GetWindowWidth(ctx), reaper.ImGui_GetWindowHeight(ctx))
            table.insert(polygon_verts, x)
            table.insert(polygon_verts, y)

            x, y = windowToScreenCoordinates(0, reaper.ImGui_GetWindowHeight(ctx))
            table.insert(polygon_verts, x)
            table.insert(polygon_verts, y)

            reaper.ImGui_DrawList_AddConvexPolyFilled(reaper.ImGui_GetWindowDrawList(ctx), reaper.new_array(polygon_verts, #polygon_verts), snapshot_list[1].color)
        end
    end
end

function drawSpheres()
    for i = 1, #snapshot_list do
        local x, y = windowToScreenCoordinates(snapshot_list[i].x * ACTION_WINDOW_WIDTH, snapshot_list[i].y * ACTION_WINDOW_HEIGHT)
        local new_color = normalizeAlphaInRange(snapshot_list[i].color, 0.1, 0.2)
        drawDot(x, y, snapshot_list[i].range * math.sqrt(ACTION_WINDOW_WIDTH^2 + ACTION_WINDOW_HEIGHT^2), new_color)
        --reaper.ImGui_DrawList_AddCircleFilled(ImGui_DrawList draw_list, number center_x, number center_y, number radius, integer col_rgba, optional integer num_segmentsIn)
    end
end

function normalizeAlphaInRange(coloreOriginale, alphaMin, alphaMax)

    local R = (coloreOriginale >> 24) & 0xFF
    local G = (coloreOriginale >> 16) & 0xFF
    local B = (coloreOriginale >> 8) & 0xFF
    local alphaOriginale = coloreOriginale & 0xFF
    
    -- Converti l'alpha originale in un valore compreso tra 0 e 1
    local alphaNormalizzato = alphaOriginale / 255
    
    -- Calcola il nuovo alpha basato sul range specificato
    -- Qui mappiamo l'alpha originale (già normalizzato) direttamente nel nuovo range
    local nuovoAlpha = alphaMin + (alphaNormalizzato * (alphaMax - alphaMin))
    
    -- Converti il nuovo alpha normalizzato in un valore intero compreso tra 0 e 255
    local alphaInt = math.floor(nuovoAlpha * 255)
    
    -- Combina R, G, B e il nuovo alpha per creare il nuovo colore
    return (R << 24) | (G << 16) | (B << 8) | alphaInt
end

function setAlphaMax(color)
    -- Estrai i componenti R, G, B dal colore originale
    local R = (color >> 16) & 0xFF
    local G = (color >> 8) & 0xFF
    local B = color & 0xFF
    
    -- Imposta l'alpha al massimo (255)
    local alphaMax = 255
    
    -- Combina R, G, B e il nuovo alpha per creare il nuovo colore
    local nuovoColore = (R << 16) | (G << 8) | B | (alphaMax << 24)
    --local nuovoColoreU32 = (a << 24) | (r << 16) | (g << 8) | b
    return nuovoColore
end

function preferencesWindow()

    -- IGNORE PARAMETERS (PRE-SAVE)
    reaper.ImGui_Text(ctx, 'Ignore Parameters')
    --reaper.ImGui_Text(ctx, 'Pre Save')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)

    local rv, rs = reaper.ImGui_InputText(ctx, 'pre-save##IgnoreParamsPreSave', IGNORE_PARAMS_PRE_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if rv then IGNORE_PARAMS_PRE_SAVE_STRING = rs end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end

    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end

    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)

    local rv, rs = reaper.ImGui_InputText(ctx, 'post-save##IgnoreParamsPostSave', IGNORE_PARAMS_POST_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())

    if rv then IGNORE_PARAMS_POST_SAVE_STRING = rs end

    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end

    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end

    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)


    -- IGNORE FX PRE-SAVE
    reaper.ImGui_Text(ctx, 'Ignore Fx')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)
    
    local rv, rs = reaper.ImGui_InputText(ctx, 'pre-save##IgnoreFXsPreSave', IGNORE_FXs_PRE_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    
    if rv then IGNORE_FXs_PRE_SAVE_STRING = rs end
    
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
    
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end
    
    
    -- IGNORE FX POST-SAVE
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)
        
    local rv, rs = reaper.ImGui_InputText(ctx, 'post-save##IgnoreFXsPostSave', IGNORE_FXs_POST_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
        
    if rv then IGNORE_FXs_POST_SAVE_STRING = rs end
        
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
        
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end

    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)


    -- IGNORE TRACKS PRE-SAVE
    reaper.ImGui_Text(ctx, 'Ignore Tracks')
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)
    
    
    local rv, rs = reaper.ImGui_InputText(ctx, 'pre-save##IgnoreTracksPreSave', IGNORE_TRACKS_PRE_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    
    if rv then IGNORE_TRACKS_PRE_SAVE_STRING = rs end
    
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
    
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end
    


    -- IGNORE TRACKS POST-SAVE
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, PREF_WINDOW_WIDTH - 85)
    
    local rv, rs = reaper.ImGui_InputText(ctx, 'post-save##IgnoreTracksPostSave', IGNORE_TRACKS_POST_SAVE_STRING, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    
    if rv then IGNORE_TRACKS_POST_SAVE_STRING = rs end
    
    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then 
        is_name_edited = false
    end
    
    if reaper.ImGui_IsItemActivated(ctx) then
        is_name_edited = true
    end
    
    reaper.ImGui_PushFont(ctx, new_line_font)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_PopFont(ctx)    

    local retval, current_item = reaper.ImGui_Combo(ctx, "Interpolation", INTERPOLATION_MODE, "IDW\0NNI\0LDW\0")

    if retval then
        INTERPOLATION_MODE = current_item

        for i = 1, #balls do
            if INTERPOLATION_MODE == 0 then
                balls[i].color = normalizeAlphaInRange(snapshot_list[i].color, 1, 1)
            elseif INTERPOLATION_MODE == 1 then
                balls[i].color = reaper.ImGui_ColorConvertDouble4ToU32(1,1,1,1)
            elseif INTERPOLATION_MODE == 2 then
                balls[i].color = normalizeAlphaInRange(snapshot_list[i].color, 1, 1)
            end
        end

    end

--[[     if reaper.ImGui_Checkbox(ctx, 'OSC', OSC_CONTROLLED) then
        OSC_CONTROLLED = not OSC_CONTROLLED
    end ]]
end

function setControlTrackEnvelopeChunks(track, fx_index)

    local envelope = reaper.GetFXEnvelope(track, fx_index, 0, 1)
    local retval, chunk = reaper.GetEnvelopeStateChunk(envelope, "", false)
    local modifiedChunk = string.gsub(chunk, "\nARM %d", "\nARM 1")
    modifiedChunk = string.gsub(modifiedChunk, "\nVIS %d %d %d", "\nVIS 1 0 0")
    reaper.SetEnvelopeStateChunk(envelope, modifiedChunk, true)

    envelope = reaper.GetFXEnvelope(track, fx_index, 1, 1)
    retval, chunk = reaper.GetEnvelopeStateChunk(envelope, "", false)
    modifiedChunk = string.gsub(chunk, "\nARM %d", "\nARM 1")
    modifiedChunk = string.gsub(modifiedChunk, "\nVIS %d %d %d", "\nVIS 1 0 0")
    reaper.SetEnvelopeStateChunk(envelope, modifiedChunk, true)
end

function setControlTrackVisibility(track, visible)
    if visible then
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        --reaper.ShowConsoleMsg('VISIBLE\n')
    else
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
        --reaper.ShowConsoleMsg('NOT VISIBLE\n')
    end
end

function getControlTrack()

    for t = 0, reaper.CountTracks(0) - 1 do
        local current_track = reaper.GetTrack(0, t)
        local retval, track_name = reaper.GetTrackName(current_track)
        if retval then
            if track_name == 'mtt_metasurface_controller' then
                local n_fx = reaper.TrackFX_GetCount(current_track)
                for f = 0, n_fx do
                    
                    local retval, fx_name = reaper.TrackFX_GetFXName(current_track, f)
                    
                    if  fx_name == 'JS: mtt_metasurface_controller [MTT/mtt_metasurface_controller]' or
                        fx_name == 'JS: mtt_metasurface_controller' or 
                        fx_name == 'mtt_metasurface_controller' then

                            return current_track, f
                    end
                end
            end
        end
    end

    reaper.InsertTrackAtIndex(reaper.CountTracks(0), 0)
    local new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)

    local trackName = "mtt_metasurface_controller"
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", trackName, true)

    reaper.TrackFX_AddByName(new_track, 'mtt_metasurface_controller', false, 1)

    return new_track, 0

end

function drawCircle(x, y, raggio, color, n_segs)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    -- draw_list,  center_x,  center_y,  radius,  col_rgba,  integer num_segmentsIn,  number thicknessIn)
    reaper.ImGui_DrawList_AddCircle(draw_list, x, y, raggio, color, n_segs, 1)
end

function drawDot(x, y, raggio, color, n_segs)
    -- Assicurati che la finestra ImGui sia già stata creata con ImGui.Begin
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- draw_list,  center_x,  center_y,  radius,  col_rgba,   num_segmentsIn)
    -- Disegna un cerchio pieno alle coordinate (x, y) con un certo raggio
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, raggio, color, n_segs)
end

function drawLine(x1, y1, x2, y2, color, thickness)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, color, thickness)
end

function onExit()
    
    --if reaper.GetProjectName(0, "") ~= '' then
        if PROJECT_NAME ~= '' then
            writeSnapshotsToFile(PROJECT_PATH .. '/ms_save')
        end
    --end
end

function initBalls()

    balls = {}

    for i = 1, #snapshot_list do

        local color = ball_default_color

        if INTERPOLATION_MODE == 0 then
            color = normalizeAlphaInRange(snapshot_list[i].color, 1, 1)
        elseif INTERPOLATION_MODE == 1 then
            color = ball_default_color
        elseif INTERPOLATION_MODE == 2 then
            color = normalizeAlphaInRange(snapshot_list[i].color,1,1)
        end

        table.insert(balls, { pos_x = snapshot_list[i].x, pos_y = snapshot_list[i].y, radius = 7, color = color, dragging = false })
    end

    return true

end

function ensureController(nomeFile, contenuto)
    local path = string.match(nomeFile, "(.+)/[^/]*$")
    if path then
        -- Usa virgolette per gestire i percorsi con spazi su macOS
        os.execute("mkdir -p \"" .. path .. "\"")
    end

    local file = io.open(nomeFile, "r")

    if file then
        file:close()
    else
        file = io.open(nomeFile, "w")
        if file then
            file:write(contenuto)
            file:close()
        else
            print("Errore nella creazione del file")
        end
    end
end

function initMS()

    PROJECT_NAME = reaper.GetProjectName(0, "")
    PROJECT_PATH = reaper.GetProjectPath(0)

    if PROJECT_NAME == '' then reaper.ShowMessageBox('You must save the project to use Metasurface.', 'Metasurface Error', 0) return false end

    
    ensureController(reaper.GetResourcePath() .. '/Effects/MTT/mtt_metasurface_controller', CONTROLLER)

    snapshot_list = {}

    if PROJECT_NAME ~= '' then
        --data, ignoreParamsPreSaveString, ignoreParamsPostSaveString, ignorePreSaveFxsString, ignorePostSaveFxsString, ignorePreSaveTracksString, ignorePostSaveTracksString, linkToControllerBool
        snapshot_list, IGNORE_PARAMS_PRE_SAVE_STRING, IGNORE_PARAMS_POST_SAVE_STRING, IGNORE_FXs_PRE_SAVE_STRING, IGNORE_FXs_POST_SAVE_STRING, IGNORE_TRACKS_PRE_SAVE_STRING, IGNORE_TRACKS_POST_SAVE_STRING, LINK_TO_CONTROLLER, INTERPOLATION_MODE = loadFromFile(reaper.GetProjectPath(0) .. '/ms_save')
    end
    
    if snapshot_list == nil then snapshot_list = {} end

    initBalls()
    updateSnapshotIndexList()

    if LINK_TO_CONTROLLER == true then
        CONTROL_TRACK, CONTROL_FX_INDEX = getControlTrack()
--[[ 
        selected_ball_default_color = reaper.ImGui_ColorConvertDouble4ToU32(0.5,0.0,0.0, 1)
        selected_ball_clicked_color = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.0,0.0, 1)

    else
        selected_ball_default_color = reaper.ImGui_ColorConvertDouble4ToU32(0.0,0.5,0.0, 1)
        selected_ball_clicked_color = reaper.ImGui_ColorConvertDouble4ToU32(0.0,0.3,0.0, 1) ]]
    end

    LAST_TOUCHED_BUTTON_INDEX = nil

    needToUpdateVoronoi = true

    return true
end

function getFxIndexByGUID(track, guid)
    
    local num_track_fx

    if track then
        num_track_fx = reaper.TrackFX_GetCount(track)
        for i = 0, num_track_fx - 1 do
            if guid == reaper.TrackFX_GetFXGUID(track, i) then
                return true, i
            end
        end
    else
        --return 0
        --reaper.MB('bob', 'bob', 0)
        return false, 0
    end
end

function getTrackByGUID(proj, guid)
    for i = 0, reaper.GetNumTracks() - 1 do
        if guid == reaper.GetTrackGUID(reaper.GetTrack(proj,i)) then
            return reaper.GetTrack(proj,i)
        end
    end
end

function printProjectSnapshotOnFile()

    local string_to_print = ''

    local file, err = io.open('/Users/mattiapersico/Desktop/debug.txt', "w")
    if not file then
        print("Impossibile aprire il file: " .. err)
        return false
    end
    file:write(string_to_print)
    file:close()

end

function printSnapIndexListOnFile()

    local string_to_print = ''

    local file, err = io.open('/Users/mattiapersico/Desktop/debugSnapList.txt', "w")
    if not file then
        print("Impossibile aprire il file: " .. err)
        return false
    end
    file:write(string_to_print)
    file:close()

end

if initMS() then
    reaper.defer(loop)
end

reaper.atexit(onExit)

