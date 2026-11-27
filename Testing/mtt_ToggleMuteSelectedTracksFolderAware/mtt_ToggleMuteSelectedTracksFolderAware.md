# mtt_ToggleMuteSelectedTracksFolderAware

## What it is
Toggles mute on the selected tracks.

- **Top-level folder parent (depth 0), fully collapsed** (`I_FOLDERCOMPACT == 2`): only the parent is muted/unmuted. Its children, at any depth, are never touched, even if they are selected (hidden selection). Several selected tracks inside the same collapsed top-level folder toggle the parent once.
- **Anything else** (top-level folder not fully collapsed, nested folders, plain tracks): classic behaviour, each selected track is toggled on its own.

## Ruled out
- Redirecting to the outermost fully collapsed ancestor at any depth (first version): the folder-aware rule is only for top-level parents.
