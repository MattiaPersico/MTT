# mtt_Shelf — where we left off

updated: 2026-09-27
- Done:
  - Drop destination of the FX drag: `insert_fx` receives the take under the cursor (`GetMediaItemTake_Item`) — the dropped-on item is selected → the FX goes on every selected item; the dropped-on item is not selected → the FX goes only on that item, not on the selected ones. Clicking a favorite and dropping on a track are unchanged (selected items, else selected tracks). User confirmed: "Ok, funziona".
- Not done:
- Waiting on:
  - Drop on a track while items are selected: the FX still goes to the selected items, not to the dropped-on track — the user did not specify (item case only).
