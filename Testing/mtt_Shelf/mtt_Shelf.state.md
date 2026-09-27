# mtt_Shelf — where we left off

updated: 2026-09-27
- Done:
  - Drop destination of the FX drag on a track: `insert_fx` now receives the track under the cursor (`BR_TrackAtMouseCursor`) — dropping on a track with no item under the pointer (arrange strip or TCP; the TCP drop used to be a no-op, "drop solo in arrange") puts the FX on that track, ignoring the selected items. Drop on an item and the click path on an FX favorite are unchanged.
- Not done:
- Waiting on:
  - Check of the new rule, user's words: "Droppare un Fx sul track panel ... inserire Fx nella traccia sotto il mouse cursor nel momento del drop" — drop on the TCP with items selected: the FX must land on that track, not on the selected items.
