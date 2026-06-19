#!/usr/bin/env npx tsx
/**
 * Finalize a social share image to exact 1280x640 PNG.
 * Center-crops to 2:1 aspect ratio, resizes, and validates file size < 1 MB.
 *
 * @param --input - Path to source image
 * @param --output - Path to output PNG (should be assets/social-share.png)
 */

import { execSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const inputIdx = args.indexOf("--input");
const outputIdx = args.indexOf("--output");

if (inputIdx === -1 || outputIdx === -1) {
  console.error(
    "Usage: finalize-social-share.ts --input <path> --output <path>",
  );
  process.exit(1);
}

const input = resolve(args[inputIdx + 1]);
const output = resolve(args[outputIdx + 1]);

if (!existsSync(input)) {
  console.error(`Input file not found: ${input}`);
  process.exit(1);
}

// Get current dimensions
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

const tmpCropped = `${output}.tmp.png`;
execSync(`cp "${input}" "${tmpCropped}"`);

// Crop to 2:1 aspect ratio
const targetRatio = 2;
const currentRatio = w / h;

if (Math.abs(currentRatio - targetRatio) > 0.01) {
  let cropW: number;
  let cropH: number;
  if (currentRatio > targetRatio) {
    // Too wide — crop width
    cropH = h;
    cropW = Math.floor(h * targetRatio);
  } else {
    // Too tall — crop height
    cropW = w;
    cropH = Math.floor(w / targetRatio);
  }
  execSync(
    `sips --cropToHeightWidth ${cropH} ${cropW} "${tmpCropped}" --out "${tmpCropped}"`,
  );
}

// Resize to 1280x640
execSync(
  `sips --resampleHeightWidth 640 1280 "${tmpCropped}" --out "${output}" -s format png`,
);

execSync(`rm -f "${tmpCropped}"`);

// Validate file size
const stat = statSync(output);
const sizeMB = stat.size / (1024 * 1024);

if (sizeMB > 1) {
  console.error(
    `❌ Social image is ${sizeMB.toFixed(2)} MB — exceeds 1 MB limit`,
  );
  process.exit(1);
}

console.log(
  `✅ Social image finalized to 1280x640 (${sizeMB.toFixed(2)} MB): ${output}`,
);
