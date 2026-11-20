# mtt item properties randomiser — where we left off

updated: 2026-11-20
- Done: Added the ReaImGui dependency/load guard and missing-take guards for Volume and Pan. Simplified Rate's Lua dispatch while keeping the native reset, step and selection sequence. Syntax and 24 baseline trace comparisons passed with Lua stubs; the empty snapshot was checked separately.
- Not done: No batched or direct-setter Rate path; native equivalence for grouped or locked items was not established. The native action count is unchanged.
- Waiting on: REAPER smoke test with grouped, locked and multi-take items, and the ReaImGui loader on the target installation.
