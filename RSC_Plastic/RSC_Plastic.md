# MTT Plastic Integration

## What it is

A Plastic SCM (Unity VCS) integration suite for REAPER that wraps the `cm` CLI tool. The suite consists of a shared library (`mtt_plastic_lib.lua`) and seven action scripts. The monitor (`mtt_plastic_monitor.lua`) is the main entry point: a draggable, color-coded dot overlaid on REAPER's GUI that shows project state and provides a click menu for Check-Out, Check-In, Revert, and Settings. The "Save (Plastic)" script (`mtt_plastic_save.lua`) replaces Cmd/Ctrl+S and checks Plastic state before saving. The remaining four scripts (checkout, checkin, revert, settings) are optional one-shot wrappers that expose the same library functions via keyboard shortcuts or toolbar buttons. All commands run cross-platform (mac + Windows) via async background scripts to never freeze the UI.

## Ruled out
