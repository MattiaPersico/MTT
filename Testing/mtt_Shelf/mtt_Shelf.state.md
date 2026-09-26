# mtt_Shelf — where we left off

updated: 2026-09-26
- Done:
  - Left scrollbar live drag (`draw_left_scrollbar`): manual hit-test on the grab/track rects, no `InvisibleButton` (the buttons repositioned every frame via `SetCursorPos` broke `IsItemActive`, so the scroll only updated on release). The press offset is latched, so the grab follows the mouse every frame with no snap; the strip ignores input while a popup or an FX drag is in front. User confirmed: "funziona perfettamente".
  - Scrollbar look: track drawn as a border only, grab 4px (centered in the 10px strip) dark gray. Colors rewritten as 0xRRGGBBAA (ReaImGui packs alpha last; the old constants were actually semi-transparent reds). User confirmed: "perfetto".
- Not done:
  - Hand cursor over draggable FX (wanted 2): deferred by the user, to be done later.
- Waiting on:
