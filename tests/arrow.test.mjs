// arrow.test.mjs: tests for tools/make_arrow.mjs and the committed yellow arrow (part of npm test).
//
// The TGA in the addon folder must be exactly what the script draws, so that the graphic stays
// reproducible; the header, the size, the region of the arrow and its colors are read back here with
// an own small TGA reader.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { arrowTga, main, OUTPUT, ARROW_BOX, SIZE } from '../tools/make_arrow.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function readTga(buffer) {
  const idLength = buffer[0];
  assert.equal(buffer[1], 0, 'no color map');
  assert.equal(buffer[2], 2, 'uncompressed true color');
  const width = buffer.readUInt16LE(12);
  const height = buffer.readUInt16LE(14);
  assert.equal(buffer[16], 32, '32 bits per pixel');
  assert.equal(buffer[17], 0x28, '8 alpha bits, origin top left');
  const start = 18 + idLength;
  assert.equal(buffer.length, start + width * height * 4, 'no extra data');
  const at = (x, y) => {
    const o = start + (y * width + x) * 4;
    return { b: buffer[o], g: buffer[o + 1], r: buffer[o + 2], a: buffer[o + 3] };
  };
  return { width, height, at };
}

test('the committed arrow is exactly the drawing of tools/make_arrow.mjs', () => {
  assert.equal(OUTPUT, path.join(repoRoot, 'PawnArrowColors', 'Textures', 'ArrowYellow.tga'));
  assert.ok(fs.readFileSync(OUTPUT).equals(arrowTga()), 'run "npm run arrow" after changing the script');
  assert.ok(arrowTga().equals(arrowTga()), 'deterministic');
  const lines = [];
  assert.equal(main(['--check'], (l) => lines.push(l), (l) => lines.push(l)), 0, lines.join('\n'));
});

test('64 x 64 with the arrow inside its box, as the texture coordinates in Core.lua expect', () => {
  const { width, height, at } = readTga(arrowTga());
  assert.equal(width, SIZE);
  assert.equal(height, SIZE);
  let x0 = SIZE;
  let y0 = SIZE;
  let x1 = -1;
  let y1 = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (at(x, y).a > 0) {
        x0 = Math.min(x0, x);
        y0 = Math.min(y0, y);
        x1 = Math.max(x1, x);
        y1 = Math.max(y1, y);
      }
    }
  }
  assert.ok(x0 >= ARROW_BOX.x0 && y0 >= ARROW_BOX.y0, `top left ${x0},${y0}`);
  assert.ok(x1 < ARROW_BOX.x1 && y1 < ARROW_BOX.y1, `bottom right ${x1},${y1}`);
  assert.ok(x1 - x0 > 0.85 * (ARROW_BOX.x1 - ARROW_BOX.x0), 'the arrow fills its box in width');
  assert.ok(y1 - y0 > 0.85 * (ARROW_BOX.y1 - ARROW_BOX.y0), 'the arrow fills its box in height');

  const core = fs.readFileSync(path.join(repoRoot, 'PawnArrowColors', 'Core.lua'), 'utf8');
  assert.match(core, new RegExp(`ns\\.ARROW_COORDS = \\{ 0, ${ARROW_BOX.x1} / ${SIZE}, 0, ${ARROW_BOX.y1} / ${SIZE} \\}`));
});

test('the arrow is yellow with a dark outline and transparent around it', () => {
  const { at } = readTga(arrowTga());
  const center = at(21, 34); // middle of the shaft
  assert.equal(center.a, 255);
  assert.ok(center.r > 200 && center.g > 150 && center.b < 80, `yellow fill ${JSON.stringify(center)}`);
  const edge = at(12, 40); // left edge of the shaft
  assert.ok(edge.r < 120 && edge.g < 100, `dark outline ${JSON.stringify(edge)}`);
  assert.equal(at(5, 40).a, 0, 'left of the shaft');
  assert.equal(at(60, 60).a, 0, 'outside the box');
});
