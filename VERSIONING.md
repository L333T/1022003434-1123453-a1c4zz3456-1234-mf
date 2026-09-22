# Master Farmer - Grindbot versioning

Copy-forward. Never rename or delete an old version folder.

## Identity

Canonical fields live in `version.lua`. `header.lua`, the GUI title, and the load log must match that table.

## On a material change

1. Copy `Master_Farmer_Grindbot_vX.Y.Z` to `Master_Farmer_Grindbot_vX.Y.(Z+1)` (or the next semver).
2. Edit **only the new folder**.
3. Update `version.lua`, every `-- Version:` / `-- Folder:` banner, GUI version text, and the load log.
4. Point the Cursor workspace at the new folder.
5. Do not bump for comment-only or rule-only edits.

## Revert

Disable the newer plugin in Sylvanas and enable the older `Master_Farmer_Grindbot_vX.Y.Z` folder.
