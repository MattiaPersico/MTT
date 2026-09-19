# mtt_Whisper_AddTakeMarkersOnTopFolderItem

## What it is

Transcribes the selected media item with whisper.cpp (a temporary glue of the item run through `whisper-cli`) and writes the transcription — plus a "B" terminator — as take markers on every item of the topmost ancestor folder track that intersects the current time selection.

## Ruled out

