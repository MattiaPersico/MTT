# mtt_envelope_stealer — where we left off

updated: 2026-11-18

- Done: version 0.21. The item-drop helper recognizes `TAKE` separators only at `<ITEM>` depth, inserts `<VOLENV` before the next take or the item close, and leaves chunks without a valid item close unchanged. The extracted helper passed 13 Lua fixtures for single and multiple takes, existing envelopes, and invalid input. The full script passed the Lua syntax check.
- Not done: no requested code changes remain.
- Waiting on: a REAPER run to confirm that a drop creates and applies Volume on the target take only, for both single- and multiple-take items. The version 0.20 checks are still awaiting a REAPER run; the previous pass ran only against a mocked API.
