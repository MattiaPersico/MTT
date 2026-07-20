-- mtt_plastic_save.lua
-- "Save (Plastic)" - da mappare su Cmd/Ctrl+S al posto del salvataggio standard.
--
-- Controlla lo stato Plastic PRIMA di scrivere su disco:
--   * fuori repo / già in checkout  -> salva e basta
--   * lockato da altri              -> avvisa, chiede se salvare comunque
--   * in repo, aggiornato, no lock  -> propone checkout+lock, poi salva
--   * in repo, NON aggiornato       -> propone versione server + checkout
--                                      (avvisa che le modifiche locali vanno perse)

local script_dir = debug.getinfo(1, 'S').source:match('@(.*)[/\\]')
local LIB = dofile(script_dir .. '/mtt_plastic_lib.lua')

local TITLE = 'MTT Plastic Save'

local function saveProject()
  reaper.Main_OnCommand(40026, 0) -- File: Save project
  LIB.markDirty()
end

local function main()
  local _, proj_path = reaper.EnumProjects(-1, '')

  -- mai salvato: lascia fare il dialogo standard di REAPER
  if proj_path == '' then
    reaper.Main_OnCommand(40026, 0)
    return
  end

  -- FAST PATH: se il monitor ha già flaggato QUESTO progetto come
  --   * in checkout (lock nostro: non può sparire da solo), oppure
  --   * fuori da un workspace Plastic (una cartella non diventa workspace da sola)
  -- salva subito senza nessun comando cm. Lo stato viene invalidato da
  -- markDirty() dopo checkin/checkout/revert, quindi non può essere stantio.
  local rt_state = LIB.getRT('state')
  if LIB.getRT('state_path') == proj_path and
     (rt_state == LIB.STATE.CHECKED_OUT or rt_state == LIB.STATE.NOT_IN_REPO) then
    reaper.Main_OnCommand(40026, 0) -- File: Save project
    return
  end

  -- un solo comando cm: fileinfo fallisce anche fuori da un workspace,
  -- quindi copre pure il check "siamo in una repo?"
  local info = LIB.fileInfo(proj_path)
  if not info then
    -- fuori da un workspace, o cm non risponde: non bloccare il salvataggio
    saveProject()
    return
  end

  -- già in checkout+lock: tutto ok
  if info.checked_out then
    saveProject()
    return
  end

  -- lock in un altro workspace (vale anche con lo stesso account su 2 macchine:
  -- se il checkout fosse nostro, lo Status locale sarebbe "checked-out")
  if info.locked_by ~= '' then
    local where = info.locked_where ~= '' and (' @ ' .. info.locked_where) or ''
    local a = reaper.ShowMessageBox(
      'Progetto lockato da: ' .. info.locked_by .. where .. '\n\n' ..
      'Puoi salvare solo in locale e NON potrai fare check-in\n' ..
      'finché il lock non viene rilasciato.\n\nSalvare comunque?',
      TITLE, 4) -- Yes / No
    if a == 6 then saveProject() end
    return
  end

  -- non in checkout: siamo aggiornati?
  local head = LIB.serverHead(proj_path)
  local out_of_date = head and info.local_cs and head > info.local_cs

  if out_of_date then
    local a = reaper.ShowMessageBox(
      'NON hai l\'ultima versione del progetto\n' ..
      '(locale cs:' .. tostring(info.local_cs) .. ' / server cs:' .. tostring(head) .. ').\n\n' ..
      'Prendere la versione server e fare checkout+lock?\n' ..
      'ATTENZIONE: le modifiche correnti andranno PERSE.',
      TITLE, 4) -- Yes / No

    if a == 6 then
      local ok, msg = LIB.doCheckoutFlow(proj_path)
      reaper.ShowMessageBox(msg, TITLE, 0)
      return
    end

    local b = reaper.ShowMessageBox(
      'Salvare comunque SENZA checkout?\n' ..
      '(il progetto resterà su una versione vecchia)',
      TITLE, 4)
    if b == 6 then saveProject() end
    return
  end

  -- aggiornati ma senza checkout: proponi checkout+lock e salva
  local a = reaper.ShowMessageBox(
    'Non hai il checkout di questo progetto.\n\n' ..
    'Fare checkout + lock e poi salvare?',
    TITLE, 3) -- Yes / No / Cancel

  if a == 2 then return end -- Cancel

  if a == 6 then -- Yes
    local dir = LIB.dirname(proj_path)
    local ok, who, out = LIB.checkout(dir)
    if ok then
      saveProject()
    elseif who then
      local b = reaper.ShowMessageBox(
        'Qualcuno ha preso il lock nel frattempo: ' .. who ..
        '\n\nSalvare comunque in locale?',
        TITLE, 4)
      if b == 6 then saveProject() end
    else
      reaper.ShowMessageBox('Checkout fallito:\n' .. tostring(out), TITLE, 0)
    end
    LIB.markDirty()
    return
  end

  -- No: salva senza checkout
  saveProject()
end

main()
