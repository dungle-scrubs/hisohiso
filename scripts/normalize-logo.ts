#!/usr/bin/env npx tsx
/**
 * Normalize any input image to exact 1000x1000 PNG.
 * Center-crops to 1:1 aspect ratio, then resizes.
 *
 * @param --input - Path to source image
 * @param --output - Path to output PNG
 */

import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const inputIdx = args.indexOf("--input");
const outputIdx = args.indexOf("--output");

if (inputIdx === -1 || outputIdx === -1) {
  console.error("Usage: normalize-logo.ts --input <path> --output <path>");
  process.exit(1);
}

const input = resolve(args[inputIdx + 1]);
const output = resolve(args[outputIdx + 1]);

if (!existsSync(input)) {
  console.error(`Input file not found: ${input}`);
  process.exit(1);
}

// Get current dimensions via sips
const info = execSync(`sips -g pixelWidth -g pixelHeight "${input}"`, {
  encoding: "utf-8",
});
const widthMatch = info.match(/pixelWidth:\s*(\d+)/);
const heightMatch = info.match(/pixelHeight:\s*(\d+)/);

if (!widthMatch || !heightMatch) {
  console.error("Could not read image dimensions");
  process.exit(1);
}

const w = parseInt(widthMatch[1], 10);
const h = parseInt(heightMatch[1], 10);

// Center-crop to square
const size = Math.min(w, h);
const cropX = Math.floor((w - size) / 2);
const cropY = Math.floor((h - size) / 2);

// Use sips for macOS-native image manipulation
const tmpCropped = `${output}.tmp.png`;

// Copy to tmp
execSync(`cp "${input}" "${tmpCropped}"`);

// Crop to square if needed
if (w !== h) {
  execSync(
    `sips --cropToHeightWidth ${size} ${size} "${tmpCropped}" --out "${tmpCropped}"`,
  );
}

// Resize to 1000x1000
execSync(
  `sips --resampleHeightWidth 1000 1000 "${tmpCropped}" --out "${output}" -s format png`,
);

// Clean tmp
execSync(`rm -f "${tmpCropped}"`);

console.log(`✅ Logo normalized to 1000x1000: ${output}`);
