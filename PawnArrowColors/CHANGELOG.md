# Changelog

## 1.1.0

Three new features, each on by default and each with its own switch (`/pac` and the settings page). With the hit cap or the weapon pairs on, the addon changes Pawn's upgrade results for the cases below; Pawn's tooltip percentages, Pawn's and ElvUI's bag arrows and the green or yellow color all follow the changed result.

- Hit cap: hit above the cap no longer counts. For every visible scale with a hit weight, the hit of an item counts only as far as it still lowers your chance to miss, measured from your hit without the equipped item it would replace; the equipped item is treated the same way. Caps by level (below 60: weapons 6%, spells 5%; on 60 against bosses: 9% and 16%) or a number of your own (`/pac hitcap 5.4`); weapon or spell cap per scale from its weights (spell cap when spell power outweighs the physical stats at least threefold), or set by hand (`/pac hitcap 2 spell`). A tooltip line names the hit that was not counted. Not applied while you wield two weapons (weapon cap), while the client hides your stats (in combat) or while Pawn tracks the best items of each scale.
- Weapon pairs: Pawn never compares two-hand weapons with one-hand weapons and off-hand items. Now a two-hand weapon is compared with your equipped main hand plus off hand, and a one-hand weapon, shield or off-hand item together with the best fitting partner from your bags with your equipped two-hand weapon. The tooltip names what was compared. While a partner's item data are still loading, Pawn's result stays and the decision follows once they arrive. `/pac pairs on | off`.
- Scale age: for every visible scale of your own (not plugin scales such as Pawn Forever's) the addon remembers on which level it first saw the scale's current weights. Three levels later (`/pac age <levels>`, 0 = off) and below level 60 the chat says so after the login and after a level up, once per scale and level; `/pac age` shows the age of every scale.
- `/pac` shows the state of the three features.

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
