# RSC_Plastic — where we left off

updated: 2026-11-26
- Done:
  - `doCheckoutInteractive` (monitor menu Check-Out + one-shot checkout script) now runs the up-to-date check on every checkout, not only from the save flow: if the .rpp local changeset is the server's latest, it does `cm co` directly (no close / discard / update / reopen, open project untouched). Not determinable (no history, private, cm error) -> old full flow. Direct checkout failing with a non-lock error -> offers the full flow.
  - New "Release Lock" in the monitor menu (enabled when checked out), `doReleaseLockFlow` in the lib: allowed only when local and server .rpp changesets match; runs `cm partial undocheckout <dir> --keepchanges` (lock released, files on disk untouched, no close / reopen). Success is judged by `fileinfo` afterwards (.rpp no longer checked out), not by the exit code. Mismatch or not comparable -> points to Revert.
  - Monitor bumped to 1.5.
- Not done:
  - No one-shot wrapper script for Release Lock (would need a new `index.xml` source entry); only the monitor menu has it.
- Waiting on:
  - The user's test in REAPER of the direct checkout (fresh session, up-to-date project) and of the out-of-date case (must still go through the full flow).
  - The user's test of Release Lock: `--keepchanges` on a directory path with `partial undocheckout` is taken from the cm docs, not run yet.
