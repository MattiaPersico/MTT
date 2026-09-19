# mtt_envelope_stealer

<!-- state: mtt_envelope_stealer.state.md · wanted: mtt_envelope_stealer.wanted.md · format: _NOTE_TEMPLATE.md
     if a note and the code disagree, the code is right and the note is fixed now. -->

## What it is

Steals an envelope from one item's audio and hands it to another item or track. From a selected reference item it analyses the active take with a peak/RMS follower (definition, attack/release, compression, gain, scale, limits), plots the curve, and carries a copy of it in a small window that follows the mouse; dragging that curve onto a target item or track writes it into the corresponding envelope — as volume, or remapped into pitch, pan or normalized volume. A dropped item can be "imposed": a corrective volume envelope is computed so its audio loudness follows the reference's profile. Based on code from mpl_Peak follower tools.

## Ruled out
