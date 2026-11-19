#!/usr/bin/env node
// make_arrow.mjs: draws the yellow upgrade arrow of Pawn Arrow Colors and writes it as a TGA file.
//
// Usage
//   node tools/make_arrow.mjs            writes PawnArrowColors/Textures/ArrowYellow.tga
//   node tools/make_arrow.mjs --check    exits with 1 if the file on disk differs from a fresh drawing
//   npm run arrow
//
// The arrow is drawn from scratch here (geometry and colors below); it is not derived from any other
// image. The output is deterministic: the same script always writes the same bytes.
//
// Image
//   64 x 64 pixels, 32 bits per pixel (BGRA, 8 bits of alpha), uncompressed true color TGA (type 2),
//   origin at the top left (image descriptor 0x28). The arrow points up and sits in the top left part
//   of the square, inside x 0..43 and y 0..47 (ARROW_BOX), the same region the bag upgrade arrow of
//   ElvUI uses in its 64 x 64 texture. On ElvUI bag slots the addon shows the whole texture (texture
//   coordinates 0..1, like ElvUI); on Blizzard bag slots it shows only ARROW_BOX (texture coordinates
//   0..44/64 and 0..48/64), so the arrow fills the rectangle of Blizzard's arrow atlas.
//
// Drawing
//   A polygon (triangle head on a rectangular shaft) is sampled with 8 x 8 samples per pixel. A sample
//   inside the polygon and closer than OUTLINE to its edge gets the outline color, a sample deeper
//   inside gets the fill color: a vertical gradient from light to deep yellow with a light band along
//   the left edges. The pixel color is the average of its samples (straight alpha, rounded).

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const OUTPUT = path.join(repoRoot, 'PawnArrowColors', 'Textures', 'ArrowYellow.tga');

export const SIZE = 64;
// Region of the arrow in pixels (inclusive start, exclusive end), see the texture coordinates in Core.lua.
export const ARROW_BOX = { x0: 0, y0: 0, x1: 44, y1: 48 };

// Polygon in pixel coordinates (x right, y down), clockwise from the tip.
const SHAPE = [
  [21.5, 1.0], // tip
  [41.5, 23.0], // right corner of the head
  [31.0, 23.0], // right shoulder
  [31.0, 46.5], // bottom right of the shaft
  [12.0, 46.5], // bottom left of the shaft
  [12.0, 23.0], // left shoulder
  [1.5, 23.0], // left corner of the head
];
const OUTLINE = 2.6; // pixels
const SAMPLES = 8; // per axis

const OUTLINE_COLOR = [58, 40, 0];
const TOP_COLOR = [255, 236, 110];
const BOTTOM_COLOR = [232, 168, 0];
const HIGHLIGHT_COLOR = [255, 250, 200];
const HIGHLIGHT_WIDTH = 2.2; // pixels inside the outline along the left edges

function inside(x, y) {
  let c = false;
  for (let i = 0, j = SHAPE.length - 1; i < SHAPE.length; j = i++) {
    const [xi, yi] = SHAPE[i];
    const [xj, yj] = SHAPE[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}

function segmentDistance(x, y, [ax, ay], [bx, by]) {
  const dx = bx - ax;
  const dy = by - ay;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
}

function edgeDistance(x, y) {
  let d = Infinity;
  for (let i = 0; i < SHAPE.length; i++) d = Math.min(d, segmentDistance(x, y, SHAPE[i], SHAPE[(i + 1) % SHAPE.length]));
  return d;
}

// Distance to the edges that face left or up-left (tip to left corner, left shaft edge).
function leftDistance(x, y) {
  return Math.min(segmentDistance(x, y, SHAPE[6], SHAPE[0]), segmentDistance(x, y, SHAPE[4], SHAPE[5]));
}

const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

function sampleColor(x, y) {
  if (!inside(x, y)) return null;
  const d = edgeDistance(x, y);
  if (d < OUTLINE) return OUTLINE_COLOR;
  const t = Math.max(0, Math.min(1, (y - SHAPE[0][1]) / (SHAPE[3][1] - SHAPE[0][1])));
  const fill = mix(TOP_COLOR, BOTTOM_COLOR, t);
  if (leftDistance(x, y) < OUTLINE + HIGHLIGHT_WIDTH) return mix(fill, HIGHLIGHT_COLOR, 0.55);
  return fill;
}

// Returns [{ r, g, b, a }] row by row from the top left, SIZE * SIZE entries.
export function drawArrow() {
  const pixels = [];
  for (let py = 0; py < SIZE; py++) {
    for (let px = 0; px < SIZE; px++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let n = 0;
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          const c = sampleColor(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES);
          if (!c) continue;
          r += c[0];
          g += c[1];
          b += c[2];
          n++;
        }
      }
      const total = SAMPLES * SAMPLES;
      pixels.push(
        n === 0
          ? { r: 0, g: 0, b: 0, a: 0 }
          : { r: Math.round(r / n), g: Math.round(g / n), b: Math.round(b / n), a: Math.round((255 * n) / total) },
      );
    }
  }
  return pixels;
}

// Uncompressed 32 bit TGA, top-left origin.
export function encodeTga(pixels, width = SIZE, height = SIZE) {
  const header = Buffer.alloc(18);
  header[2] = 2; // uncompressed true color
  header.writeUInt16LE(width, 12);
  header.writeUInt16LE(height, 14);
  header[16] = 32; // bits per pixel
  header[17] = 0x28; // 8 alpha bits, origin top left
  const data = Buffer.alloc(width * height * 4);
  pixels.forEach((p, i) => {
    data[i * 4] = p.b;
    data[i * 4 + 1] = p.g;
    data[i * 4 + 2] = p.r;
    data[i * 4 + 3] = p.a;
  });
  return Buffer.concat([header, data]);
}

export function arrowTga() {
  return encodeTga(drawArrow());
}

export function main(argv, log = console.log, logError = console.error) {
  const tga = arrowTga();
  if (argv.includes('--check')) {
    const onDisk = fs.existsSync(OUTPUT) ? fs.readFileSync(OUTPUT) : null;
    if (onDisk && onDisk.equals(tga)) {
      log(`${path.relative(repoRoot, OUTPUT)} is up to date`);
      return 0;
    }
    logError(`${path.relative(repoRoot, OUTPUT)} differs from a fresh drawing; run "npm run arrow"`);
    return 1;
  }
  fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
  fs.writeFileSync(OUTPUT, tga);
  log(`${path.relative(repoRoot, OUTPUT)}: ${tga.length} bytes`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
