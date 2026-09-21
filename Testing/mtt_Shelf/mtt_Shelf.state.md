# mtt_Shelf — where we left off

updated: 2026-09-21
- Done:
  - Preset system (was wanted 1): a `+Preset` popup in the shelf window saves the current favorites list as a named snapshot into a single global file `.mtt_shelf_presets.txt` in REAPER's resource path, shared across all projects so a project with an empty shelf can load a premade setup; the popup lists saved presets, click loads one (replaces the favorites and consolidates them into the project file) and `x` deletes one.
  - Wanted 1: after dropping an FX on a target (track or item), the FX's UI window opens automatically.
- Not done:
  - None.
- Waiting on:
  - The in-REAPER run: save a preset from a shelf with favorites, load it in a project with an empty shelf, delete one with `x`; the list is re-read only when the script restarts.
  - Testing the new FX-drag-and-open behavior.
