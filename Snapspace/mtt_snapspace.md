# mtt_snapspace

## What it is

A 2D performance surface for live automation. Each "ball" in the main window is a saved snapshot of FX parameter states (project → tracks → FX); moving the cursor — or a touch device over OSC (`Snapspace_x` / `Snapspace_y` / `Snapspace_Touch`) — interpolates the parameters between the snapshots (IDW, natural-neighbor, or linear-distance weighting) and applies them, either directly to the project's FX or through a dedicated control track. Snapshots are saved per project (and a global file), the space shows a Voronoi diagram of the snapshots, and a preferences window covers OSC address, filters and behavior.

## Ruled out

- 2026-11-14 — mode 1 value jumps when the cursor crosses a Voronoi cell border: NOT a wrong neighbour lookup (the lookup through the neighbour polygons' centroids matched the polygon map in 480 of 480 random cells). The neighbour set itself changes at the border, and the weights are not zero there.
