# mtt_Shelf — where we left off

updated: 2026-09-22
- Done:
  - Drag preview (wanted #4): the preview is a fully invisible window (`SetNextWindowBgAlpha(0)`, `WindowBorderSize 0`, `WindowPadding 0,0`, `NoDecoration|NoBackground|NoMove|NoSavedSettings|AlwaysAutoResize`) positioned at `mouse - grab point`, so the cursor stays on the same relative coordinates of the button for the whole drag — confirmed working in REAPER. The grab point is captured once on the first drag frame in `render_favorite_button` (guarded by `not isDraggingFx`; re-capturing per frame would pin the preview back to the source button), and `isDraggingFx`/`draggedFx` are module locals now (they were implicit globals). The preview `Button` renders the favorite name (`name .. "##shelf_drag_preview"`) with the same 4 type colors as the source, so it reads as a copy of the dragged button instead of an empty square.
- Not done:
  - None.
- Waiting on:
  - In-REAPER run of the preview look: while dragging, the button must read as a copy of the source favorite (name + dark-green border), the window invisible. Confirmed → remove wanted #4.
  - In-REAPER run: hover a favorite button and check the ring shows the palette colors rotating around the button (no visible seam where the lap closes, no flicker), then move the mouse away and check the 1px per-type border (blue-grey / dark-green) comes back.
  - In-REAPER run of the case that raised the assertion (undocked shelf with favorites; hover the last favorite then move away): no `ImGui_End` boundary error, and the undocked auto-height still covers the whole slot.
  - Testing the FX-drag-and-open behavior.
  - Preset save from a shelf with favorites, load in a project with an empty shelf, delete one with `x`.
