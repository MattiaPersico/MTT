<!--
NOTE TEMPLATE — this file lives at the repo root as _NOTE_TEMPLATE.md and is never filled in itself.

A script gets THREE note files, named after it, beside each other:

    <same path as the script>.md          what it is, what was ruled out
    <same path as the script>.state.md    where the work left off
    <same path as the script>.wanted.md   the user's list

  Testing/mtt_Shelf.lua  ->  Testing/mtt_Shelf.md
                             Testing/mtt_Shelf.state.md
                             Testing/mtt_Shelf.wanted.md

WHY THREE FILES AND NOT THREE SECTIONS

A file is replaced with `write_file`: whole, in one call, with nothing to locate, match or
bound. A section inside a shared file is replaced by matching the old text exactly, and
when that match fails the fallback is an edit anchored on one line — which is an append,
whatever the intent. That is how a previous session's "Done" lines survive a rewrite and
how "Waiting on" disappears.

So the split is not tidiness. The parts that must be replaced in full no longer share a
file with the parts that must not be touched, and the rewrite cannot degrade into an
append because there is no partial edit to fall back to.

Start a note by copying each skeleton below, without this comment.

RULES — all three files

- Written in English, in impersonal third person. Say "the user" when a person must be
  named at all; never "I", never a name. Most sentences need neither. A file that drifts
  into another language mid-bullet was appended to rather than rewritten.

RULES — <name>.md

- "What it is" is purpose, not implementation. One short paragraph. If it names a
  function, that belongs in the code instead.

- "Ruled out" is not a list of decisions. A decision that can sit on the line it concerns
  IS a comment on that line — put it in the source and leave this file alone. What goes
  here is what has no line to attach to, which in practice is almost only ever a wrong
  diagnosis, because the fix is the absence of it. One dated line each:

      - YYYY-MM-DD — <symptom>: NOT <the attractive wrong cause>. <the real one>

  A section that stays empty for months is this filter working, not failing.

RULES — <name>.state.md

- **Replaced with `write_file`, whole, from the top. Never edited in place.** Write the
  file as it should read now; anything not written is gone, which is the point.

- It is state, not a log. It answers one question: if a new session picked this work up
  right now, what would it need to know?

      Done         only what THIS session changed. Earlier work is in the code and in git
                   history — it is not carried forward here.
      Not done     asked for and not delivered, with why.
      Waiting on   what is still open: a check in REAPER, a decision, an answer. An older
                   change whose check has not come back yet is carried here as one short
                   line — it does not stay behind as a "Done" bullet.

- `updated:` is the date and nothing else. **Git does not belong in this file**: which
  commit contains what is a repository question, and `git log -- <this file>` answers it
  better than any hand-written field. Never record a commit hash, a branch, a working-tree
  state, or "still needs committing" — none of it is about the work on this script, and
  all of it is stale the moment it is written.

RULES — <name>.wanted.md

- This file belongs to the user. Do not add an entry, do not reword, reorder, split, merge
  or "clarify" one, and do not delete one because it looks obsolete — a line you did not
  write is not yours to interpret. If an entry is unclear, ask.

- The one permitted edit is **removing an entry in the same pass that implements it**,
  renumbering what remains so the list stays 1..n. Rewrite the file whole, like the state
  file. Leaving an implemented entry in place is the failure this file has.

- **Do only the entry you were asked for.** This is a menu the user picks from, not a queue
  to work through. Implementing a second entry because it looks related, trivial or already
  half-done by your change is not initiative: it is a change nobody asked for, in a file
  only the user can test, and it spends the session on work that was not wanted yet. If
  your change genuinely opens another entry up, say so in one line and leave it in the list.

- A number points at the list as just read, not at a lasting name. Before acting on "do
  number 3", re-read this file in the same turn rather than trusting a listing from earlier
  in the conversation.

- What an implemented entry still needs — a check in REAPER, a decision — goes in the state
  file, not here.

- Do not copy these rules into the note files. The header line in each skeleton is enough;
  this file is the single place they live.
-->

---

<!-- ============ <path>/<script>.md ============ -->

# <script file name>

<!-- state: <script>.state.md · wanted: <script>.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

## Ruled out

---

<!-- ============ <path>/<script>.state.md ============ -->

# <script file name> — where we left off

<!-- Rewritten whole with write_file at the end of the work, never edited in place. -->

updated: YYYY-MM-DD

- Done:
- Not done:
- Waiting on:

---

<!-- ============ <path>/<script>.wanted.md ============ -->

# <script file name> — wanted

<!-- The user's list. Remove an entry only in the pass that implements it, renumbering what
     remains. Never add one, never reword one. -->

1.
2.
3.
