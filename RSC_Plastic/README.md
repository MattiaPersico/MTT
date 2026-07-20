# MTT Plastic Integration 2.0

Integrazione Plastic SCM (Unity VCS) per REAPER. Riscrittura completa: cross-platform (mac + Windows), zero configurazione obbligatoria, UI mai bloccata.

## File

| File | Cosa fa |
|---|---|
| `mtt_plastic_lib.lua` | Libreria condivisa: contiene TUTTA la logica (comandi cm + flussi interattivi). **Non è un'azione**, non caricarla come script. |
| `mtt_plastic_monitor.lua` | Monitor sempre attivo: solo un pallino colorato sopra la GUI. **Click sinistro = menu** con Check-Out, Check-In, Revert, Refresh, Impostazioni, Chiudi (voci abilitate in base allo stato). Trascinabile, posizione ricordata. Comandi `cm` in background: REAPER non si congela mai. Basta caricare questo per avere tutto. |
| `mtt_plastic_save.lua` | "Save (Plastic)". Da mappare su **Cmd/Ctrl+S**. Controlla lo stato *prima* di salvare: propone update + checkout + lock quando serve. |
| `mtt_plastic_checkin.lua` | Wrapper opzionale: check-in con commento + rilascio lock. |
| `mtt_plastic_checkout.lua` | Wrapper opzionale: update + checkout esclusivo (lock). |
| `mtt_plastic_revert.lua` | Wrapper opzionale: revert alla versione server (con conferma). |
| `mtt_plastic_settings.lua` | Wrapper opzionale: impostazioni (path `cm`, intervallo refresh, template commento). |

Gli script wrapper sono comodi solo per assegnare scorciatoie/toolbar dedicate: tutte le funzioni sono già nel menu del monitor.

## Installazione

1. Copia l'intera cartella `mtt_plastic` in `Scripts/` dentro la resource path di REAPER (`Options → Show REAPER resource path`). I file devono restare **nella stessa cartella** (gli script caricano la lib per path relativo).
2. `Actions → Show action list → New action → Load ReaScript`: carica i 5 script (tutti tranne `mtt_plastic_lib.lua`).
3. Rimappa **Cmd+S / Ctrl+S** su `mtt_plastic_save.lua` (Action list → seleziona lo script → Add shortcut). Il salvataggio standard resta disponibile da menu File.
4. (Consigliato) Aggiungi `mtt_plastic_monitor.lua` alla toolbar o a `__startup.lua` per averlo sempre attivo.

## Requisiti

- **Plastic SCM / Unity VCS client** installato (`cm`). Path auto-rilevato: app standard mac, `C:\Program Files\PlasticSCM5\client` su Windows, altrimenti PATH. Path custom impostabile da `mtt_plastic_settings`.
- **ReaImGui** (ReaPack → ReaTeam Extensions) solo per il monitor.
- **js_ReaScriptAPI** (ReaPack) *opzionale*: con l'estensione il pallino viene ancorato come offset dall'angolo alto-destra della finestra REAPER — trascinalo una volta accanto a "Monitoring FX" e resta incollato lì anche spostando/ridimensionando la finestra. Senza estensione: posizione assoluta salvata (fissa sullo schermo, non segue la finestra).
- Account/server Plastic: **non** vanno configurati qui. Stanno in `client.conf` del client Plastic (configurato una volta con l'app Plastic/Gluon); `cm` li usa da solo.

## Stati del monitor

| Colore | Stato |
|---|---|
| grigio | progetto non salvato |
| rosso | fuori da un workspace Plastic |
| blu | in repo ma NON aggiornato all'ultima versione |
| verde | in repo, aggiornato, checkout disponibile |
| giallo | in checkout + lock (tuo) |
| arancio | lockato da un altro utente |

## Note tecniche / limiti

- I comandi girano tramite script temporanei `.sh`/`.bat` con output su file: niente `io.popen` bloccante, niente finestre cmd che lampeggiano, quoting dei path corretto (spazi ok).
- Parsing basato su `cm fileinfo --format="{Status};{RevisionChangeset};{LockedBy};{LockedWhere}"` e `cm history --format="{changesetid}"` invece delle frasi in inglese dell'output umano. Se la tua versione di `cm` usa nomi campo diversi, i punti da ritoccare sono `FILEINFO_FORMAT` e `cmd_history` in `mtt_plastic_lib.lua`. Se il parsing fallisce il monitor mostra "stato sconosciuto"/"non verificabile" invece di rompersi.
- Il controllo "sei aggiornato?" confronta il changeset del file `.rpp` locale con l'ultimo sul server (best effort). Il lock invece è ricorsivo sulla cartella progetto, come nella versione 1.x.
- Il lock esclusivo funziona solo se sul server sono configurate le regole di lock (`lock.conf`) per i file interessati — comportamento identico alla versione precedente.
- Il flusso checkout chiude la tab progetto, scarta le modifiche locali (`cm undo -R`), aggiorna (`cm partial update`), fa `cm co -R` e riapre con `Main_openProject("noprompt:...")` (niente più rilancio di REAPER da CLI).
