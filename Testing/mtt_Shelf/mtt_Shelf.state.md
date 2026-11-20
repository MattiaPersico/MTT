# mtt_Shelf — where we left off

updated: 2026-11-19
- Done:
  - `insert_fx`: the FX now lands only on the active take of each target item (`reaper.GetActiveTake`), not on every take of the item.
  - Left scrollbar: the grab keeps LEFT_SB_GRAB_MARGIN_Y from the track outline at both ends while scrolling too (it touched it at the top and bottom). Buttons rectangular (FrameRounding 0, was 3).
- Not done:
- Waiting on:
  - User to test: dropping an FX on a multi-take item adds it only to the active take (click on a selected multi-take item too, and the drag-drop path).
  - User to test: the first separator sits at the top border (docked mode still has a ~1px Dummy + item-spacing below it); bottom margin is now gone too.
