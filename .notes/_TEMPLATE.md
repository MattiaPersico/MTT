<!--
NOTE TEMPLATE — this file lives at .notes/_TEMPLATE.md and is never filled in itself.

To start a note for a script, copy everything BELOW the horizontal rule into
.notes/<same relative path as the script>.md — e.g. Testing/mtt_Shelf.lua becomes
.notes/Testing/mtt_Shelf.md. Do not copy this comment block.

FOUR SECTIONS, FOUR LIFETIMES
  What it is          purpose of the script; changes almost never
  Ruled out           wrong explanations already chased; expected to stay empty for months
  Where we left off   replaced in full every time, never appended to
  Wanted              the user's list; the agent may delete from it, never write to it

WRITING RULES
- Impersonal third person. Say "the user" when a person must be named at all; never "I",
  never a name. Most sentences need neither.

- "What it is" is purpose, not implementation. One short paragraph. If it names a
  function, that belongs in the code instead.

- "Ruled out" is not a list of decisions. A decision that can sit on the line it concerns
  IS a comment on that line — put it in the source and leave this section alone. What goes
  here is what has no line to attach to, which in practice is almost only ever a wrong
  diagnosis, because the fix is the absence of it. One dated line each:

      - YYYY-MM-DD — <symptom>: NOT <the attractive wrong cause>. <the real one>

  A section that stays empty for months is this filter working, not failing.

- "Where we left off" answers one question: if a new session picked this work up right
  now, what would it need to know? So it carries what is NOT done as much as what is, and
  what the work is waiting on. It is rewritten whole — never added to — at the same moment
  the work would be reported as done.

- The `updated:` line records the commit AND the state of the working tree. A note
  pointing at a commit that does not contain the code it describes is worse than no note.

- "Wanted" belongs to the user. Do not add to it, do not reword, reorder, split, merge or
  "clarify" an entry, and do not delete one because it looks obsolete — a line you did not
  write is not yours to interpret. The only permitted edit is removing an entry in the
  same pass that implements it, renumbering what remains so the list stays 1..n. A number
  is therefore a pointer to the list **as just read**, not a lasting name: before acting on
  "do number 3", re-read this section in the same turn rather than trusting a listing from
  earlier in the conversation. What the implementation still needs — a run in REAPER, a
  decision — goes in "Where we left off", not here. If an entry is unclear, ask; do not
  guess it into something else.

- Do not copy these rules into the note. The two lines in the skeleton are enough; this
  file is the single place they live.
-->

---

# <script file name>

<!-- Format: .notes/_TEMPLATE.md · "Where we left off" is replaced in full, never appended
     to · "Wanted" is the user's: delete an entry when you implement it, never write one ·
     if this note and the code disagree, the code is right and the note is fixed now. -->

## What it is

## Ruled out

## Where we left off

updated: YYYY-MM-DD · commit <sha> · tree: <clean | modified: path, path>

- Done:
- Not done:
- Waiting on:

## Wanted

1.
2.
3.
