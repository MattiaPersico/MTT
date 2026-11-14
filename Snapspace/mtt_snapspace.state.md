# mtt_snapspace — where we left off

updated: 2026-11-14
- Done:
  - Optimization pass, `minor_version` 57. Interpolation results are unchanged (same parameter values on every frame of a scripted gesture in the three modes, checked outside REAPER with a stubbed API).
    - One `TrackFX_SetParam` per parameter per frame instead of one per group entry (8 snapshots, 240 differing parameters: 13,440 calls per frame became 240).
    - `updateSnapshotIndexList` rebuilt with cached track / FX / name-filter lookups and a keyed grouping; same groups, entries and order.
    - The Voronoi diagram is cached: the resize check compared against a size that was never updated, so the diagram was rebuilt on every frame. Polygon→snapshot map and vertex arrays are built once per diagram, borders are drawn once per frame.
    - `saveSelected` reads and filters track / FX names once instead of once per parameter.
  - Fixes:
    - Crash on Shift+click delete when no snapshot is selected (right after loading).
    - Crash on an unreadable `snapspace_save` (it now loads as empty).
    - Crash in mode 1 with Smooth = 0, or after a controller playback in another mode (`previousInterpolatedValues` did not exist yet); crash in controller mode + mode 1 with fewer than two snapshots.
    - With Smooth = 0 the parameter list was not rebuilt at gesture start, so moved snapshots kept their old positions.
    - Smoothing factor clamped to 1 (long frames made the cursor overshoot and bounce).
    - Window move/resize lock was decided by the last snapshot only; now by any hovered snapshot.
    - Ignore filters: text is matched literally (it was a Lua pattern: `(` raised an error), spaces are ignored on both sides, an empty word (trailing `, `) no longer matches everything; the post-snap parameter filter read the name of the wrong parameter when some parameters were ignored at save time.
    - Cmd/Ctrl+S ran its action on every frame while held; defaults for an empty Spacebar / Cmd+S field were swapped; the OSC socket was not closed on project switch; `LINK` play stop left the smoothing state armed; range 0 produced 0/0 in mode 2; style pops moved out of the `visible` block; control track pointer validated before use.
- Not done:
  - Duplicated group entries are still there: a snapshot is added to a parameter's group once per other snapshot holding a different value, which biases the weights (values 0, 0, 1 at an equidistant point give 0.50, not 0.33). Left as is because removing them changes what the three modes output.
  - The nine near-identical gesture functions (3 inputs × 3 modes) were not merged.
  - `verify` was not run: the docs tools were not available in the session that made the changes. No new API name was introduced; changed call sites reuse calls already present in the file.
  - Nothing was run inside REAPER.
- Waiting on:
  - The user's test of 0.57 in REAPER.
  - The user's decision on the duplicated group entries and on the mode 1 / mode 2 findings (mode 1: not exact on a snapshot, depends on window size, jumps at cell borders; mode 2: normalised weights make the range edge a hard step).
