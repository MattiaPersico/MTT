# mtt_Shelf — where we left off

updated: 2026-09-27
- Done:
  - FX drop on a track (track panel/TCP or arrange row, no item under the cursor): `insert_fx` takes `drop_track` — the FX goes into that track's chain (`TrackFX_AddByName`), ignoring selected items and selected tracks. Drop on an item (take) and the click path (selected items, else selected tracks) are unchanged from the earlier pass. Drops on the MCP remain a no-op.
- Not done:
- Waiting on:
  - Test: drop a favorite FX on a track's track panel, and on the empty part of a track row in the arrange — the FX must land in that track's chain, not in the selected items.
