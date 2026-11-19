# Changelog

## 1.0.1

- Fixed: version 1.0.0 never saw Pawn as ready in the game (it checked a flag that Pawn keeps private), so `/pac` said "Pawn is not available" and no arrow was colored; the addon now asks Pawn through its public function `PawnIsReady`.
- If Pawn was not ready within ten seconds after the login, `/pac` and `/pac refresh` now look for Pawn again instead of staying off until the next reload.
- `/pac` names the reason when nothing is colored (Pawn not loaded, a Pawn function missing, or Pawn not ready yet).

## 1.0.0

First version.

- Pawn's green upgrade arrow on bag items stays green when the item is an upgrade for your main Pawn scale and turns yellow when it is an upgrade only for another visible scale (or only an item level upgrade).
- Works on ElvUI's bags and bank (setting "Upgrade Icon") and on Blizzard's bags with Pawn's own arrows (Pawn option "Show bag upgrade advisor").
- Main scale per character; default: the first scale Pawn shows for the character. `/pac` (also `/pawnarrowcolors`) and a page under Options > AddOns.
- Own yellow arrow graphic, or the original arrow tinted yellow (`/pac style tint`).
