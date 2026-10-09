# mtt_sample_rate_switch_stop — where we left off

updated: 2026-10-09
- Done: fixed the restore — the saved rate is read as a number and compared numerically (the old string-vs-number `==` was always false, so the rate never came back); audio re-inits only when the rate actually differs
- Not done:
- Waiting on: user test in REAPER
