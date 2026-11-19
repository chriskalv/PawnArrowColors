# PawnArrowColors

AddOn to colorize Pawn Arrows in your inventory in WoW Forever.

**Pawn Arrow Colors** (Interface 16001) splits Pawn's green upgrade arrow on bag items in two: the arrow stays **green** when the item is an upgrade for your main Pawn scale and turns **yellow** when it is an upgrade only for another visible scale. It works on ElvUI's bags and bank and on Blizzard's bags, and it only colors arrows that Pawn or ElvUI already show.

The addon itself is the folder [`PawnArrowColors/`](PawnArrowColors/); its [README](PawnArrowColors/README.md) describes the rule, the commands, the settings and what is not checked in the game yet. The [CHANGELOG](PawnArrowColors/CHANGELOG.md) lists the changes per version.

## Install

1. Download `PawnArrowColors-<version>-forever.zip` from the [Releases](https://github.com/chriskalv/PawnArrowColors/releases) page, or install and update it through an addon manager that reads GitHub releases (for example WoWUp).
2. Extract it into the `Interface\AddOns` folder of your WoW installation, so that `Interface\AddOns\PawnArrowColors\PawnArrowColors.toc` exists.
3. Restart the game and enable **Pawn Arrow Colors** in the addon list. `/pac` shows the state, `/pac list` the scales, `/pac main <number>` chooses the main scale.

Requirements: Pawn. For ElvUI bags ElvUI's setting *Bags > Upgrade Icon* must be on; for Blizzard bags Pawn's option *Show bag upgrade advisor*.

## What it does not do

- It does not add or hide arrows; Pawn (Blizzard bags) or ElvUI (ElvUI bags) decide where an arrow is shown.
- It does not change Pawn's tooltips, its scales or any other hint of Pawn, and it changes no code of Pawn or ElvUI.
- Blizzard's bank shows no upgrade arrows, so there is nothing to color there.

## Development

The Lua tests run without the game client, in [fengari](https://github.com/fengari-lua/fengari) (Lua in JavaScript) with stand-ins of the WoW API, Pawn, ElvUI's bag module and Blizzard's bags. With Node.js 22 in the repository root:

```
npm install
npm test
npm run arrow
npm run release
```

`npm test` runs the Lua tests with `tools/addon_test.mjs` (TOC resolved, every Lua file checked as Lua 5.1, then the tests in `tests/PawnArrowColors/`), the tests of the release script in `tests/release.test.mjs` and the tests of the arrow graphic in `tests/arrow.test.mjs`. `npm run arrow` draws the yellow arrow `PawnArrowColors/Textures/ArrowYellow.tga` with `tools/make_arrow.mjs` (64 x 64, 32-bit TGA; the script always writes the same bytes, and the test checks that the committed file matches). `npm run release` writes `dist/PawnArrowColors-<version>-forever.zip` and `dist/release.json` with `tools/release.mjs`: the version from the TOC, the addon folder as the only root of the zip, no development files; the release.json follows the format of the BigWigs packager (name, version, file name of the zip, flavor `forever` and the interface number from the TOC line `## Interface-Forever:`). Upload both files together as the assets of the GitHub release, so that addon managers detect updates.

Releases are made by the GitHub Actions workflow *Release* (Actions > Release > Run workflow, with the version from the TOC; *dry run* only builds the assets): it checks the TOC version and the tag, runs the tests, builds the zip and the `release.json`, takes the notes from the matching section of the CHANGELOG and publishes the release with the tag `v<version>`.
