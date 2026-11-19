# Pawn Arrow Colors

A small addon for **WoW Forever** (Interface 16001) on top of [Pawn](https://www.curseforge.com/wow/addons/pawn). Pawn puts a green arrow on bag items that are an upgrade for *any* scale shown in its tooltip. Pawn Arrow Colors splits that arrow in two:

- **green**: the item is an upgrade for your **main scale** (it may be an upgrade for other scales as well);
- **yellow**: the item is an upgrade only for **other** visible scales, or only an item level upgrade.

It colors only the arrows Pawn or ElvUI already show. It never adds or hides an arrow, and it does not change Pawn's tooltips or any other hint of Pawn.

## Requirements

- **Pawn** (written and tested against the code of Pawn 2.14.4; written for the scales of Pawn Forever as well, which is not checked in the game yet).
- **ElvUI bags** (optional): ElvUI's own setting *Bags > Upgrade Icon* must be on; ElvUI then shows the arrow in its bags and bank.
- **Blizzard bags**: Pawn's own option *Show bag upgrade advisor* must be on (Pawn > Options); Pawn then shows the arrow in Blizzard's bags. Blizzard's bank has no upgrade arrows.

## Main scale

The main scale is saved per character by Pawn's internal scale name. Default: the first scale Pawn shows for the character, in the order of Pawn's scale list (the scales listed as visible for the character in Pawn's window). If the saved scale is hidden in Pawn or no longer exists, the default is used and the chat says so once; the saved choice is kept for when the scale comes back.

## Commands

| Command | Effect |
|---|---|
| `/pac` | state: on or off, style, main scale, which bags are colored |
| `/pac list` | the visible Pawn scales with numbers; `*` marks the main scale; scales with the same name show their internal name in brackets |
| `/pac main <number or name>` | choose the main scale, e.g. `/pac main 2` or `/pac main Retribution`; if several scales have that name, choose by number |
| `/pac main default` | back to the default (first visible scale) |
| `/pac on`, `/pac off`, `/pac toggle` | color the arrows, or leave every arrow green |
| `/pac style yellow`, `/pac style tint` | the own yellow arrow (default), or the original arrow desaturated and tinted yellow |
| `/pac refresh` | forget the cached results and repaint |
| `/pac options` | open the settings page |

`/pawnarrowcolors` works like `/pac`. The same settings are on the page *Options > AddOns > Pawn Arrow Colors*: a checkbox for the colors, a dropdown with the visible scales and a dropdown for the style.

## How it works

- **ElvUI**: a secure post-hook on the function of ElvUI's bag module that shows or hides the arrow of a slot (`UpdateItemUpgradeIcon`); it also runs when ElvUI asks Pawn again later.
- **Blizzard bags**: secure hooks on the arrow texture of each bag button (`SetShown`, `Show`, `Hide`), found through post-hooks on the bag frames' `UpdateItems`. They follow every change Pawn makes to the arrow, including Pawn's delayed retries.
- For each item link the addon asks Pawn once which visible scales the item is an upgrade for and remembers the answer. The answers are forgotten when Pawn resets its bag arrows (scale or option changes in Pawn, and Pawn's own check after a gear change), when you choose another main scale, and one second after a gear change if Pawn has not reset its arrows by then (in combat Pawn waits); the visible arrows are then repainted on the next frame.
- A yellow arrow is put back to its original state (graphic, texture coordinates, color, saturation) as soon as the button shows a main-scale upgrade, no arrow or the colors are turned off.
- If Pawn or ElvUI lack a function the addon expects (another version), the affected part turns itself off and says so once in the chat.
- The addon writes no fields to Blizzard's or ElvUI's frames; the only change to Blizzard's arrow textures is the secure hooks (`hooksecurefunc`) on `SetShown`, `Show` and `Hide`, the same kind of hook Pawn itself uses.

## Not checked in the game yet

This first version is tested against stand-ins of Pawn, ElvUI and Blizzard's bags, not yet in the client. To check in WoW Forever: the yellow arrow's position and size next to the green one (ElvUI and Blizzard bags), the default main scale with Pawn Forever's scales, a scale hidden in Pawn, a gear change, the ElvUI bank, the settings page, `/reload` with the saved main scale, and no taint message when you use a bag item in combat (Blizzard bags).
