# mtt_Whisper_AddTakeMarkersOnTopFolderItem

## What it is

Transcribes speech with whisper.cpp and writes the text — plus a "B" terminator — as take markers on every item of the topmost folder track that overlaps the time selection (or the selected item's bounds when there is no time selection). It can be run on an item inside a folder (its audio is transcribed) or directly on the parent item of a folder track (the portions of the child items under the range are mixed and transcribed; the parent item only receives the markers). whisper-cli runs in the background, so REAPER stays responsive.

## Ruled out

