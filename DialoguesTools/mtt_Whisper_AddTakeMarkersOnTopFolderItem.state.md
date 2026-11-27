# mtt_Whisper_AddTakeMarkersOnTopFolderItem — where we left off

updated: 2026-11-24
- Done:
  - Runs on the parent item of a folder track too (requested by the user): a top-level folder track is its own top folder; the child item portions under the range (unmuted ones; all of them when every one is muted) are mixed and transcribed. The parent item's own take is never analyzed ("vanno selezionate le porzioni child ovviamente, altrimenti che analizza?").
  - Audio read with a take audio accessor into a 16 kHz mono WAV (padded to 1.1 s) instead of the temporary glue via the focus-dependent smart-copy action; no temporary track, no extra undo point. A muted item is unmuted only while it is read.
  - whisper-cli runs in the background (ExecProcess -2 + defer poll, timeout MAX_WAIT_S, killed in atexit); transcribed once instead of once per target item; its stderr is shown on failure.
  - When no take returns audio, the message lists per item: mute, channels, accessor span, read start, block statuses.
  - No time selection: the selected item's bounds are the range. Marker positions account for playrate and are clamped to each item; re-running a range replaces its own markers instead of doubling them.
  - Messages and comments moved to English.
- Not done:
- Waiting on:
  - First test by the user, with the parent item selected (then still reading its own take): "The takes returned no audio in the range." Re-test pending with the child portions as source. `verify` not run: the REAPER docs tools were not available in this session.
