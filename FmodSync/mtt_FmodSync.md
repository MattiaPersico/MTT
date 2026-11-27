# mtt_FmodSync

## What it is
Links a REAPER project to an FMOD Studio project. The user chooses, from REAPER, the FMOD asset folder each asset goes to; the script renders the assets, copies them into the FMOD project and keeps them in sync (new renders, new takes, files gone from REAPER) by talking to the running FMOD Studio through its scripting terminal (TCP 3663). The link and the per-project settings live in a file next to the RPP; per-user settings (where each FMOD project sits on disk) live in REAPER's ExtState.

## Ruled out
