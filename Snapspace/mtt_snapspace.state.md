# mtt_snapspace — where we left off

updated: 2026-11-14
- Done:
  - `minor_version` 58, two changes the user asked for ("si e si"):
    - One group entry per snapshot in `updateSnapshotIndexList`. A snapshot used to be entered once per other snapshot holding a different value, which multiplied its weight in the three modes (values 0, 0, 1 at an equidistant point gave 0.50; now 0.33). Where no two snapshots share a value the output is unchanged (largest difference 2e-15 over a scripted gesture, modes 0 and 2).
    - Mode 1 is now natural neighbour (Sibson) interpolation, the method of AudioMulch's Metasurface: the cursor is one more Voronoi site and each snapshot weighs the share of the cursor's cell taken from its own cell. Cells are the action area clipped by the bisectors (`updateNaturalNeighborCells`), weights are computed once per frame (`naturalNeighborWeights`). The gaussian kernel, the per-cell neighbour lookup and the fixed 0.6 value lag are gone. The diagram is still drawn by `voronoi.lua`.
  - Checked outside REAPER with a stubbed API: mode 1 gives the snapshot's values with the cursor on it (error 0), weights sum to 1 and move by at most 0.013 per half-pixel step with 9 snapshots; the earlier crash and filter cases still pass.
- Not done:
  - The combo still labels mode 1 "Nearest Neighbors" and mode 2 "Inverse Distance Weighting (range)".
  - The nine near-identical gesture functions (3 inputs × 3 modes) were not merged.
  - `verify` was not run: the docs tools were not available in the session that made the changes. No new API name was introduced.
  - Nothing was run inside REAPER.
- Waiting on:
  - The user's test of 0.57 and 0.58 in REAPER.
  - Four snapshots on the corners (panner L R Ls Rs): along the top edge the front/back parameter still dips towards the centre, 0.19 in mode 0 and 0.13 in mode 1 (left/right is now exactly linear in mode 1). A straight path there needs bilinear interpolation, which no mode does: the user has not asked for it.
