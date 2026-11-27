-- mtt_fmodsync_config.lua
-- Two places for settings:
--   project: a JSON file next to the .RPP, "<rpp name>.fmodsync.json", so that
--            several RPPs in one folder keep separate links. It names the FMOD
--            project by its file name only (no absolute path): it is shared.
--   user:    REAPER's ExtState (section EXT, persistent), per machine: where the
--            user keeps each FMOD project on disk ("fspro:<file name>" -> path).

local M = {}

M.EXT = 'mtt_FmodSync'
M.SUFFIX = '.fmodsync.json'
M.FORMAT = 1

local SEP = reaper.GetOS():find('Win') and '\\' or '/'
M.SEP = SEP

-- "C:\a\b.fspro" or "/a/b.fspro" -> "b.fspro". Pure.
function M.basename(path)
  return (tostring(path or ''):match('([^/\\]+)$')) or ''
end

-- Folder of a file path, without the trailing separator. Pure.
function M.dirname(path)
  return (tostring(path or ''):match('^(.*)[/\\][^/\\]*$')) or ''
end

-- The project file for an RPP path ("" when the project was never saved). Pure.
function M.config_path(rpp_path)
  if not rpp_path or rpp_path == '' then return nil end
  return (rpp_path:gsub('%.[Rr][Pp][Pp]$', '')) .. M.SUFFIX
end

function M.new_config()
  return { format = M.FORMAT, fmod_project = nil, assets = {}, takes = {} }
end

local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local s = f:read('a')
  f:close()
  return s
end

-- Returns the config table, or nil + reason. A missing file is not an error:
-- it gives a new, empty config.
function M.load(json, rpp_path)
  local path = M.config_path(rpp_path)
  if not path then return nil, 'save the REAPER project first' end
  local s = read_file(path)
  if not s then return M.new_config() end
  local cfg, _, err = json.decode(s)
  if type(cfg) ~= 'table' then return nil, 'cannot read ' .. path .. ': ' .. tostring(err) end
  cfg.assets = cfg.assets or {}
  cfg.takes = cfg.takes or {}
  return cfg
end

-- Writes to a temporary file first, then replaces the old one: a crash halfway
-- leaves the previous config intact.
function M.save(json, rpp_path, cfg)
  local path = M.config_path(rpp_path)
  if not path then return false, 'save the REAPER project first' end
  local text = json.encode(cfg, { indent = true, keyorder = { 'format', 'fmod_project', 'name_template', 'block_gap', 'render_dir', 'assets', 'takes' } })
  local tmp = path .. '.tmp'
  local f, err = io.open(tmp, 'wb')
  if not f then return false, err end
  f:write(text)
  f:close()
  os.remove(path)
  local ok, err2 = os.rename(tmp, path)
  if not ok then return false, err2 end
  return true
end

-- Per-user: where this machine keeps the FMOD project called `name`.
function M.user_fspro_path(name)
  if not name or name == '' then return nil end
  local p = reaper.GetExtState(M.EXT, 'fspro:' .. name)
  if p == '' then return nil end
  return p
end

function M.set_user_fspro_path(name, path)
  reaper.SetExtState(M.EXT, 'fspro:' .. name, path, true)
end

-- The asset folders of an FMOD project, read from disk: in FMOD Studio the
-- folders of the assets browser are the real folders under "<project>/Assets".
-- Returns a tree { name, rel, children = {...} } (rel uses "/", like FMOD's asset
-- paths), or nil + reason. depth caps runaway recursion through links.
function M.scan_asset_folders(fspro_path, max_depth)
  local root = M.dirname(fspro_path) .. SEP .. 'Assets'
  if not reaper.file_exists(fspro_path) then return nil, 'FMOD project not found: ' .. fspro_path end
  max_depth = max_depth or 12
  local function walk(abs, rel, depth)
    local node = { name = M.basename(abs), rel = rel, children = {} }
    if depth > max_depth then return node end
    local names, i = {}, 0
    while true do
      local sub = reaper.EnumerateSubdirectories(abs, i)
      if not sub then break end
      if sub:sub(1, 1) ~= '.' then names[#names + 1] = sub end
      i = i + 1
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, n in ipairs(names) do
      node.children[#node.children + 1] =
        walk(abs .. SEP .. n, rel == '' and n or (rel .. '/' .. n), depth + 1)
    end
    return node
  end
  local tree = walk(root, '', 0)
  tree.name = 'Assets'
  return tree
end

return M
