# Pawn Arrow Colors

A small addon for **WoW Forever** (Interface 16001) on top of [Pawn](https://www.curseforge.com/wow/addons/pawn). Pawn puts a green arrow on bag items that are an upgrade for *any* scale shown in its tooltip. Pawn Arrow Colors splits that arrow in two:

- **green**: the item is an upgrade for your **main scale** (it may be an upgrade for other scales as well);
- **yellow**: the item is an upgrade only for **other** visible scales, or only an item level upgrade.

Since version 1.1.0 it also corrects two blind spots of Pawn's upgrade results and gives one hint, each with its own switch and on by default:

- **Hit cap**: hit above the cap no longer counts as if it were useful.
- **Weapon pairs**: two-hand weapons are compared with one-hand weapon and off-hand pairs, which Pawn never does.
- **Scale age**: a chat line when a scale's weights are several levels old.

The colors only follow the arrows Pawn or ElvUI show. The hit cap and the weapon pairs change Pawn's own upgrade result for the cases they concern; Pawn and ElvUI then show or hide their arrows by that result, and Pawn's tooltip shows the changed percentage.

## Requirements

- **Pawn** (written and tested against the code of Pawn 2.14.8 for Forever; written for the scales of Pawn Forever as well, which is not checked in the game yet).
- **ElvUI bags** (optional): ElvUI's own setting *Bags > Upgrade Icon* must be on; ElvUI then shows the arrow in its bags and bank.
- **Blizzard bags**: Pawn's own option *Show bag upgrade advisor* must be on (Pawn > Options); Pawn then shows the arrow in Blizzard's bags. Blizzard's bank has no upgrade arrows.
- The hit cap and the weapon pairs work with Pawn's default comparison *Versus equipped gear* (Pawn > Options > Upgrade comparisons). With *Track for each scale* they change nothing.

## Main scale

The main scale is saved per character by Pawn's internal scale name. Default: the first scale Pawn shows for the character, in the order of Pawn's scale list (the scales listed as visible for the character in Pawn's window). If the saved scale is hidden in Pawn or no longer exists, the default is used and the chat says so once; the saved choice is kept for when the scale comes back.

## Hit cap

Pawn values every stat linearly: hit above the point where nothing misses any more still counts in full, so every further piece with hit looks like an upgrade. With the hit cap on, for every visible scale with a positive hit weight:

- The hit of an item counts only up to the **room** left below the cap: cap minus your hit without the equipped item the new one would replace. Example: cap 6%, you have 5% with 1% on the equipped ring, a new ring has 3%. Without the old ring you have 4%, so 2% of the new ring count and all of the old ring's 1%.
- The **equipped item** is treated the same way, so an item that carries hit beyond the cap does not look better than it is.
- **Two slots** (rings; one-hand weapons that the scale lets go into the off hand): Pawn compares a new item with the weaker of the two equipped ones; the addon does the same, with the values after the cap, and measures the room without that weaker item. An empty ring slot stays what it is in Pawn: any ring is an upgrade there.
- Pawn's value line in the tooltip (the item's score) stays Pawn's linear value. Pawn's upgrade percentage, the bag arrows and the color use the value with the cap. A line below Pawn's lines says how much hit counted, for example `Retribution: hit counted up to the cap 6.0% (you 5.0%): this item 2.0% of 3.0%, Ring of One 1.0% of 1.0%`.

**Caps** with the setting *auto* (default), from the attack tables of the [MythicSim Forever engine](https://github.com/sage3648/mythicsim-forever-engine) (MIT, commit `772410e`, 2026-11-23; `src/prepare/attack.rs` `new_attack_table`, `src/core/fight/melee.rs` physical hit and miss, `src/mechanics/damage.rs` `spell_chance_to_miss`):

| Level | Target | Weapons | Spells |
|---|---|---|---|
| below 60 | two levels above you | 6.0% (base miss 6%) | 5.0% (base miss 6%, a spell always keeps 1%) |
| 60 | boss (three levels above) | 9.0% (base miss 8% plus 1% hit suppression) | 16.0% (base miss 17%, less the 1% that stays) |

A number of your own (`/pac hitcap 5.4`) replaces both caps.

**Weapon or spell cap**: the addon compares two weights of the scale: P, the largest weight of `Strength`, `Agility`, `Ap` and `Rap`, and S, the largest weight of spell power (`SpellPower`, `SpellDamage`, `Healing`, the school damage stats). The scale counts against the spell cap when S is above 0 and P is below a third of S, otherwise against the weapon cap; a scale with neither counts against the weapon cap when it weighs a weapon DPS stat, otherwise against the spell cap. Weapon DPS alone does not decide, because casters' scales often weigh a wand's `RangedDps` highly. With the scales of Pawn Forever this gives the spell cap to mages, warlocks, shadow priests, Balance, Elemental and the Shockadin, the weapon cap to warriors, rogues, hunters, Retribution, Enhancement and the tanks, including the Protection Paladin (its seals, Judgement and white swings roll against the melee table; its spells against the spell table, which the one cap does not show). The third is a fixed choice, not a measurement. For the weapon cap the addon reads your ranged hit when the scale weighs `RangedDps` above every melee DPS stat, otherwise your melee hit. `/pac hitcap <scale number> weapon | spell | auto` overrides the rule per scale.

**Your hit** comes from the client, as the character sheet adds it up: `GetHitModifier()` (melee), `GetRangedHitModifier()` or `GetSpellHitModifier()` plus `GetCombatRatingBonus` of the matching hit rating. The hit an equipped item adds is its `HitRating` as Pawn reads it from the tooltip, with its enchantment; for the spell cap also its `SpellHitRating`. Pawn values only `HitRating` (on Forever Pawn merges a scale's spell hit weight into it and reads lines "with spells" as `SpellHitRating`, which it values 0), so that is the hit that is capped; for a spell scale the addon assumes that this hit adds to your spell hit. An item's `SpellHitRating` still fills the room under the spell cap, for the candidate and the equipped item alike: it fills it first, and the item's `HitRating` counts as far as room is left. An item worth 0 or less to Pawn (an `X` value of the scale) is not capped, and a capped value never goes below 0, so the percentage stays Pawn's for an equipped item worth 0.

**Not applied** (Pawn's result stays):

- while you **wield two weapons** (the weapon cap; your white swings miss far more often than the cap says, so hit keeps its value);
- while the client **hides your stats** (in combat and in instances the hit functions can return secret values; they are never compared or computed with, and the decisions are made again once the hit can be read);
- when Pawn's own result for a scale differs from what the addon computes for it without the cap (a rule of Pawn the addon does not reproduce, for example heirlooms or artifacts);
- for trinkets (Pawn never rates them) and while Pawn tracks the best items of each scale.

The decisions are made again when the gear changes, on a level up (other caps on 60), after talents, buffs or anything else changes your hit (checked half a second after the client reports new stats), and when a scale changes in Pawn.

## Weapon pairs

Pawn never compares a two-hand weapon with one-hand weapons, shields and off-hand items: with a two-hand weapon equipped no one-hand item is an upgrade, and the other way round. With weapon pairs on, for every visible scale:

- **Two-hand weapon in the bags, one-hand items equipped**: the two-hand weapon against the sum of the equipped main hand and off hand.
- **One-hand, main-hand or off-hand weapon, shield or off-hand item, two-hand weapon equipped**: the item plus the best fitting partner from your bags against the two-hand weapon. "Best" means the pair worth the most for that scale. A main-hand candidate without a partner counts alone (partner worth 0); an off-hand candidate without a main-hand partner is no upgrade.
- The result appears where Pawn shows upgrades: Pawn's percentage in the tooltip, the arrow in Blizzard's and ElvUI's bags, green or yellow by the main scale. A line in the tooltip names what was compared, for example `Protection: with Kite Shield, against Greatsword` or `Retribution: against Mace + Kite Shield`.

Rules:

- Pawn's own rules stay: an `X` value of the scale makes an item worth 0, so it is neither an upgrade nor a partner; the scale's switches *Don't show upgrades for 1H items / 2H items*; an upgrade must be at least 0.5% better; with *Track for each scale* nothing changes.
- A partner must be usable now: your level at least its required level, and not an item Pawn marks as never usable for your class. A one-hand weapon (or an off-hand weapon) goes into the off hand only when the scale lets it (no `X` on `IsOffHand`, which Pawn's class templates set for classes without dual wield) and the client says you can dual wield. A one-hand weapon candidate is always put into the main hand.
- The candidate is not its own partner; a second copy of the same item in the bags is.
- While a fitting item in the bags has no data yet (the client or Pawn is still loading it, for example right after the login), the addon makes no decision and keeps none: Pawn's result stays until the item data have arrived; then the addon decides again and the arrows follow.
- The hit cap applies to the pair values (both hands are taken off to measure the room); a pair with a weapon in the off hand counts as dual wielding.
- Only the bags are searched (bags 0 to 4), not the bank. The weapons and off-hand items in the bags are read once and again after a change of the bags; the result per scale and item is kept until the gear, Pawn's scales or those bag items change. When they change, Pawn is asked to rate its bag arrows again.

## Scale age

Stat weights measured at one level grow old while you level. For every visible scale of your own (not the scales of plugins such as Pawn Forever) the addon remembers per character on which level it first saw the scale's current content (an identifier from the scale's name and all of its values). When the values change, the count starts again at the current level. Once you are three levels further (`/pac age <levels>`, `0` or `off` turns the hint off) and below level 60, the chat says so after the login and after a level up, at most once per scale and level:

`the weights of the scale Retribution are from level 20, you are level 23 now; consider determining them again.`

The first time version 1.1.0 runs, it counts from your level at that login. `/pac age` shows the age of every scale.

## Commands

| Command | Effect |
|---|---|
| `/pac` | state: colors on or off, style, main scale, which bags are colored, and the state of the scale age, the hit cap and the weapon pairs |
| `/pac list` | the visible Pawn scales with numbers; `*` marks the main scale; scales with the same name show their internal name in brackets |
| `/pac main <number or name>` | choose the main scale, e.g. `/pac main 2` or `/pac main Retribution`; if several scales have that name, choose by number |
| `/pac main default` | back to the default (first visible scale) |
| `/pac on`, `/pac off`, `/pac toggle` | color the arrows, or leave every arrow green |
| `/pac style yellow`, `/pac style tint` | the own yellow arrow (default), or the original arrow desaturated and tinted yellow |
| `/pac age`, `/pac age <levels>`, `/pac age on \| off` | the age of every scale; the number of levels for the hint (default 3, `off` = 0) |
| `/pac hitcap`, `/pac hitcap on \| off` | the caps, your hit and the cap of every scale; the hit cap on or off |
| `/pac hitcap auto`, `/pac hitcap <percent>` | caps by level (default), or one number for weapons and spells |
| `/pac hitcap <scale> weapon \| spell \| auto` | which cap a scale counts against (scale by number or name) |
| `/pac pairs`, `/pac pairs on \| off` | the state of the weapon pairs; on or off |
| `/pac refresh` | forget the cached results and repaint; if Pawn was not ready after the login, look for Pawn again |
| `/pac options` | open the settings page |

`/pawnarrowcolors` works like `/pac`. The same settings are on the page *Options > AddOns > Pawn Arrow Colors*: a checkbox for the colors, a dropdown with the visible scales, a dropdown for the style, a dropdown for the scale age (off, after 1 to 10 levels), a checkbox and a dropdown for the hit cap (automatic or 1% to 17%) and a checkbox for the weapon pairs. The cap per scale is set with `/pac hitcap` only.

## How it works

- **ElvUI**: a secure post-hook on the function of ElvUI's bag module that shows or hides the arrow of a slot (`UpdateItemUpgradeIcon`); it also runs when ElvUI asks Pawn again later.
- **Blizzard bags**: secure hooks on the arrow texture of each bag button (`SetShown`, `Show`, `Hide`), found through post-hooks on the bag frames' `UpdateItems`. They follow every change Pawn makes to the arrow, including Pawn's delayed retries.
- For each item link the addon asks Pawn once which visible scales the item is an upgrade for and remembers the answer. The answers are forgotten when Pawn resets its bag arrows (scale or option changes in Pawn, and Pawn's own check after a gear change), when you choose another main scale, and one second after a gear change if Pawn has not reset its arrows by then (in combat Pawn waits); the visible arrows are then repainted on the next frame.
- **Hit cap and weapon pairs**: the addon replaces Pawn's global function `PawnIsItemAnUpgrade` by a function that calls Pawn's original and then changes its answer for the scales the features concern. Pawn calls that function by its global name for its tooltip (`PawnUpdateTooltip`) and for its bag arrow check (`PawnShouldItemLinkHaveUpgradeArrowUnbudgeted`, which ElvUI asks too), and the colors ask it as well, so all of them show one result. To compare like Pawn, the addon reads the equipped items through `PawnGetItemDataForInventorySlot` and their values through `PawnGetSingleValueFromItem` (the values without enchantments, as Pawn compares them), the value of 1% hit through `PawnGetItemValue` (with the scale's normalization). The tooltip line comes from a secure post-hook on `PawnUpdateTooltip`. When a setting, your hit or the partners in your bags change, the addon calls Pawn's `PawnResetBags`, so that Pawn rates its bag arrows again. ElvUI does not follow `PawnResetBags` (it asks Pawn only when it updates a slot), so the addon then also calls ElvUI's own `UpdateItemUpgradeIcon` for every ElvUI slot with an arrow, as ElvUI's slot update does. The tooltip lines show only while Pawn's option to show upgrades in tooltips is on, since only then does Pawn's tooltip ask for the result.
- **Scale age**: reads the scales' values from Pawn's saved variable `PawnCommon.Scales` and keeps its own records in the addon's saved variables per character.
- A yellow arrow is put back to its original state (graphic, texture coordinates, color, saturation) as soon as the button shows a main-scale upgrade, no arrow or the colors are turned off.
- The addon starts when Pawn reports through its public function `PawnIsReady` that it can rate items (right after the login, or up to ten seconds later). It only uses Pawn's public functions and settings; the list with their places in Pawn's code is in `tests/pawn_names.test.mjs` of the repository.
- If Pawn or ElvUI lack a function the addon expects (another version), the affected part turns itself off and says so once in the chat; `/pac` names the reason. Without one of the Pawn functions the hit cap and the weapon pairs need, Pawn's results stay as they are. An error inside the hit cap or the weapon pairs also leaves Pawn's results as they are until `/reload` and says so once.
- The addon writes no fields to Blizzard's, ElvUI's or Pawn's frames and tables; its changes are the secure hooks (`hooksecurefunc`) on Blizzard's arrow textures, ElvUI's arrow function and Pawn's `PawnResetBags` and `PawnUpdateTooltip`, the replaced `PawnIsItemAnUpgrade`, and the calls of ElvUI's `UpdateItemUpgradeIcon` after a change.

## Limits

- The caps are the engine's attack tables for a target two levels above you (below 60) and a boss (on 60); against other targets the real cap is lower or higher. Weapon skill above your level's base (racial or from items) lowers the real weapon cap; the addon does not count it.
- While you wield two weapons the weapon cap is not applied at all (see above).
- One cap per scale: a hybrid scale (the Protection Paladin) counts all its hit against the weapon cap, although its spells could still use hit up to the spell cap; `/pac hitcap <scale> spell` switches it.
- With Pawn's *Track for each scale* neither the hit cap nor the weapon pairs change anything.
- The weapon pairs search the bags only; the best pair is the best for each scale on its own, not one pair for all scales.
- The scale age counts from the first login with version 1.1.0, not from the day the weights were measured.

## Checked in the game

- Version 1.0.0 did not recognize Pawn in WoW Forever (Pawn 2.14.4 with ElvUI): `/pac` reported "Pawn is not available" and no arrow was colored. It read Pawn's initialization flag, which Pawn keeps local to its own file. Version 1.0.1 asks Pawn's public function `PawnIsReady` instead; the tests now hide that flag in the stand-in of Pawn as Pawn does, and a test checks that the addon uses only Pawn's public names.
- Versions 1.0.1 and 1.1.0 are not checked in the game yet.

## Not checked in the game yet

The rest is tested against stand-ins of Pawn, ElvUI and Blizzard's bags, not yet in the client; outside the repository the comparison of the hit cap and the weapon pairs was also run against Pawn's own `PawnIsItemAnUpgrade` (Pawn 2.14.8 loaded in a Lua test bench): the addon's comparison without the cap matched Pawn's answer for every one of 186 scale answers. To check in WoW Forever: that `/pac` shows the main scale after the login, the yellow arrow's position and size next to the green one (ElvUI and Blizzard bags), the default main scale with Pawn Forever's scales, a scale hidden in Pawn, a gear change, the ElvUI bank, the settings page, `/reload` with the saved main scale, no taint message when you use a bag item in combat (Blizzard bags); for 1.1.0 that `/pac hitcap` shows the same hit as the character sheet, the tooltip lines of the hit cap and the weapon pairs, and the scale age hint after a level up.
