#!/usr/bin/env node
/**
 * Download CloudflareSpeedTest (CFST) v2.3.5 into src-tauri/sidecar/.
 * Usage:
 *   node scripts/fetch-cfst.mjs
 *   node scripts/fetch-cfst.mjs x86_64-pc-windows-msvc
 *   node scripts/fetch-cfst.mjs --force
 */
import { createWriteStream, readdirSync } from "node:fs";
import { access, chmod, copyFile, mkdir, rename, rm } from "node:fs/promises";
import { pipeline } from "node:stream/promises";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, "..");
const sidecarDir = path.join(appRoot, "src-tauri", "sidecar");
const FORCE = process.argv.includes("--force") || process.argv.includes("-f");
const VERSION = "v2.3.5";

const PLATFORM_MAP = {
  "x86_64-pc-windows-msvc": { platform: "win32", arch: "amd64" },
  "i686-pc-windows-msvc": { platform: "win32", arch: "386" },
  "aarch64-pc-windows-msvc": { platform: "win32", arch: "arm64" },
  "x86_64-apple-darwin": { platform: "darwin", arch: "amd64" },
  "aarch64-apple-darwin": { platform: "darwin", arch: "arm64" },
  "x86_64-unknown-linux-gnu": { platform: "linux", arch: "amd64" },
  "aarch64-unknown-linux-gnu": { platform: "linux", arch: "arm64" },
};

const args = process.argv.slice(2).filter((a) => a !== "--force" && a !== "-f");
const targetArg = args[0];
const triple =
  targetArg && PLATFORM_MAP[targetArg]
    ? targetArg
    : execSync("rustc -vV", { encoding: "utf8" }).match(/host: (.+)/)?.[1];

if (!triple || !PLATFORM_MAP[triple]) {
  console.error(`Unsupported or unknown target triple: ${triple}`);
  process.exit(1);
}

const { platform, arch } = PLATFORM_MAP[triple];
const isWin = platform === "win32";
const isLinux = platform === "linux";
const url = `https://github.com/XIU2/CloudflareSpeedTest/releases/download/${VERSION}/${
  isLinux
    ? `cfst_linux_${arch}.tar.gz`
    : platform === "darwin"
      ? `cfst_darwin_${arch}.zip`
      : `cfst_windows_${arch}.zip`
}`;

const outName = `viasix-cfst-${triple}${isWin ? ".exe" : ""}`;
const outPath = path.join(sidecarDir, outName);
const plainPath = path.join(sidecarDir, isWin ? "viasix-cfst.exe" : "viasix-cfst");

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function download(url, dest) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download ${url} -> HTTP ${res.status}`);
  await pipeline(Readable.fromWeb(res.body), createWriteStream(dest));
}

function findBinary(dir) {
  const names = readdirSync(dir, { withFileTypes: true });
  for (const entry of names) {
    if (!entry.isFile()) continue;
    const n = entry.name.toLowerCase();
    if (
      n === "cfst" ||
      n === "cfst.exe" ||
      n.startsWith("cloudflarespeedtest") ||
      n === "cloudflare_speedtest" ||
      n === "cloudflare_speedtest.exe"
    ) {
      return path.join(dir, entry.name);
    }
  }
  for (const entry of names) {
    if (entry.isDirectory() && !entry.name.startsWith(".")) {
      const nested = findBinary(path.join(dir, entry.name));
      if (nested) return nested;
    }
  }
  return null;
}

async function main() {
  await mkdir(sidecarDir, { recursive: true });
  if (!FORCE && (await exists(outPath))) {
    console.log(`already present: ${outPath}`);
    if (!(await exists(plainPath))) {
      await copyFile(outPath, plainPath);
      if (!isWin) await chmod(plainPath, 0o755);
    }
    return;
  }

  console.log(`fetching ${url}`);
  const tmpDir = path.join(sidecarDir, ".tmp-cfst");
  await rm(tmpDir, { recursive: true, force: true });
  await mkdir(tmpDir, { recursive: true });
  const archive = path.join(tmpDir, path.basename(url));
  await download(url, archive);

  if (url.endsWith(".tar.gz")) {
    execSync(`tar -xzf "${archive}" -C "${tmpDir}"`, { stdio: "inherit" });
  } else {
    execSync(`unzip -o "${archive}" -d "${tmpDir}"`, { stdio: "inherit" });
  }

  const bin = findBinary(tmpDir);
  if (!bin) throw new Error(`CFST binary not found in ${archive}`);
  await rename(bin, outPath);
  if (!isWin) await chmod(outPath, 0o755);
  await copyFile(outPath, plainPath);
  if (!isWin) await chmod(plainPath, 0o755);
  await rm(tmpDir, { recursive: true, force: true });
  console.log(`wrote ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
