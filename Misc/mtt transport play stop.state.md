# mtt transport play stop — where we left off

updated: 2026-11-20
- Done: Replaced the SWS lookup and action with a native repeat reset before the toggle. Preserved the cursor move, toggle, loop-point removal and final reset in order. Four Lua mock cases passed (SWS present or absent, transport stopped or playing). Saved-file Lua verification found no signature errors; three variable command arguments were not checked.
- Not done:
- Waiting on: REAPER confirmation of the toggle without SWS and of cursor and linked time-selection behavior.
