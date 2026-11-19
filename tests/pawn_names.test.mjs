// Static check: every name of the form Pawn... in the addon's Lua code is a public name of Pawn (a
// global that Pawn itself defines and that other addons can reach) or one of the addon's own names.
//
// Background: version 1.0.0 read PawnIsInitialized, which is a file-local variable of Pawn.lua and so
// always nil for other addons; the addon never saw Pawn as ready. A name that is not in the list below
// makes this test fail, so a new dependency on Pawn has to be checked against Pawn's code first.
//
// Collected from the Lua syntax tree (comments and prose in strings do not count): every identifier
// (globals, locals, fields, keys) and every string literal that is a whole name, as in
// _G["PawnGetItemData"] or hooksecurefunc("PawnResetBags", ...).
//
// Run with: node --test tests/pawn_names.test.mjs (part of npm test)

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import luaparse from 'luaparse';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const addonDir = path.join(repoRoot, 'PawnArrowColors');

// Public names of Pawn the addon may use. Sources: Pawn 2.14.4, paths inside the AddOns/Pawn folder.
export const PAWN_PUBLIC = new Map([
  ['PawnIsReady', 'Pawn.lua:4953 function PawnIsReady() (section "Pawn API"; returns the local PawnIsInitialized)'],
  ['PawnGetItemData', 'Pawn.lua:1328 function PawnGetItemData(ItemLink)'],
  ['PawnIsItemAnUpgrade', 'Pawn.lua:3590 function PawnIsItemAnUpgrade(Item, DoNotRescan)'],
  ['PawnGetAllScalesEx', 'Pawn.lua:5227 function PawnGetAllScalesEx()'],
  ['PawnResetBags', 'Pawn.lua:1142 function PawnResetBags()'],
  ['PawnCommon', 'Pawn.toc:6 ## SavedVariables: PawnCommon; created in Pawn.lua:582'],
]);

// The addon's own names that start with Pawn.
export const OWN = new Map([
  ['PawnArrowColorsCharDB', 'PawnArrowColors.toc ## SavedVariablesPerCharacter'],
]);

const NAME = /^Pawn\w*$/;

function stringValue(node) {
  if (typeof node.value === 'string') return node.value;
  const raw = node.raw || '';
  const m = /^(['"])([\s\S]*)\1$/.exec(raw) || /^\[(=*)\[([\s\S]*)\]\1\]$/.exec(raw);
  return m ? m[2] : null;
}

// Returns a Map name -> list of "file:line" for every Pawn... name in the Lua source.
export function pawnNames(source, file = 'chunk') {
  const ast = luaparse.parse(source, { luaVersion: '5.1', locations: true, comments: false });
  const found = new Map();
  const add = (name, node) => {
    if (!NAME.test(name)) return;
    const where = `${file}:${node.loc ? node.loc.start.line : '?'}`;
    if (!found.has(name)) found.set(name, []);
    found.get(name).push(where);
  };
  const walk = (node) => {
    if (Array.isArray(node)) {
      for (const n of node) walk(n);
      return;
    }
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Identifier') add(node.name, node);
    if (node.type === 'StringLiteral') {
      const v = stringValue(node);
      if (v !== null) add(v, node);
    }
    for (const [key, value] of Object.entries(node)) {
      if (key === 'loc' || key === 'range') continue;
      if (value && typeof value === 'object') walk(value);
    }
  };
  walk(ast);
  return found;
}

function addonFiles() {
  const toc = fs.readFileSync(path.join(addonDir, 'PawnArrowColors.toc'), 'utf8');
  return toc.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#') && l.endsWith('.lua'));
}

test('the addon uses only public Pawn names (and its own)', () => {
  const files = addonFiles();
  assert.ok(files.length >= 3, 'Lua files from the TOC');
  const all = new Map();
  for (const f of files) {
    const src = fs.readFileSync(path.join(addonDir, f), 'utf8');
    for (const [name, places] of pawnNames(src, f)) {
      all.set(name, [...(all.get(name) || []), ...places]);
    }
  }
  const unknown = [...all.keys()].filter((n) => !PAWN_PUBLIC.has(n) && !OWN.has(n)).sort();
  assert.deepEqual(unknown.map((n) => `${n} (${all.get(n).join(', ')})`), [],
    'names of the form Pawn... that are not in the list of public Pawn names; check them in Pawn\'s code (global, not local) and add them with their source');
  const unused = [...PAWN_PUBLIC.keys(), ...OWN.keys()].filter((n) => !all.has(n)).sort();
  assert.deepEqual(unused, [], 'listed names the addon no longer uses; remove them from the list');
});

test('the check finds Pawn names in code and ignores comments and prose', () => {
  const src = [
    '-- PawnInComment is ignored',
    'local a = PawnIsInitialized',
    'local b = _G["PawnHidden"]',
    'hooksecurefunc("PawnHooked", f)',
    'local t = { PawnKey = 1 }',
    'print("Pawn is not ready; PawnInProse stays prose")',
    'local c = x.PawnField',
  ].join('\n');
  assert.deepEqual([...pawnNames(src).keys()].sort(),
    ['PawnField', 'PawnHidden', 'PawnHooked', 'PawnIsInitialized', 'PawnKey']);
});

test('PawnIsInitialized is not a public name (it is local in Pawn.lua:23)', () => {
  assert.equal(PAWN_PUBLIC.has('PawnIsInitialized'), false);
  assert.equal(OWN.has('PawnIsInitialized'), false);
});
