#!/usr/bin/env node
/**
 * Download a platform-matched mihomo binary into src-tauri/sidecar/.
 * Usage:
 *   node scripts/fetch-mihomo.mjs
 *   node scripts/fetch-mihomo.mjs x86_64-pc-windows-msvc
 *   node scripts/fetch-mihomo.mjs --force
 */
import { createReadStream, createWriteStream, readdirSync } from "node:fs";
import { access, chmod, copyFile, mkdir, rename, rm } from "node:fs/promises";
import { pipeline } from "node:stream/promises";
import { createGunzip } from "node:zlib";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, "..");
const sidecarDir = path.join(appRoot, "src-tauri", "sidecar");
const FORCE = process.argv.includes("--force") || process.argv.includes("-f");

const PLATFORM_MAP = {
  "x86_64-pc-windows-msvc": { platform: "win32", arch: "x64" },
  "i686-pc-windows-msvc": { platform: "win32", arch: "ia32" },
  "aarch64-pc-windows-msvc": { platform: "win32", arch: "arm64" },
  "x86_64-apple-darwin": { platform: "darwin", arch: "x64" },
  "aarch64-apple-darwin": { platform: "darwin", arch: "arm64" },
  "x86_64-unknown-linux-gnu": { platform: "linux", arch: "x64" },
  "aarch64-unknown-linux-gnu": { platform: "linux", arch: "arm64" },
};

const META_MAP = {
  "win32-x64": "mihomo-windows-amd64-v2",
  "win32-ia32": "mihomo-windows-386",
  "win32-arm64": "mihomo-windows-arm64",
  "darwin-x64": "mihomo-darwin-amd64-v2",
  "darwin-arm64": "mihomo-darwin-arm64",
  "linux-x64": "mihomo-linux-amd64-v2",
  "linux-arm64": "mihomo-linux-arm64",
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
const assetStem = META_MAP[`${platform}-${arch}`];
if (!assetStem) {
  console.error(`No mihomo asset mapping for ${platform}-${arch}`);
  process.exit(1);
}

const isWin = platform === "win32";
const outName = `viasix-mihomo-${triple}${isWin ? ".exe" : ""}`;
const outPath = path.join(sidecarDir, outName);
const plainPath = path.join(sidecarDir, isWin ? "viasix-mihomo.exe" : "viasix-mihomo");

async function exists(p) {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

async function latestVersion() {
  const res = await fetch(
    "https://github.com/MetaCubeX/mihomo/releases/latest/download/version.txt",
  );
  if (!res.ok) throw new Error(`version.txt HTTP ${res.status}`);
  return (await res.text()).trim();
}

async function download(url, dest) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download ${url} -> HTTP ${res.status}`);
  await pipeline(Readable.fromWeb(res.body), createWriteStream(dest));
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

  const version = await latestVersion();
  const ext = isWin ? "zip" : "gz";
  const url = `https://github.com/MetaCubeX/mihomo/releases/download/${version}/${assetStem}-${version}.${ext}`;
  console.log(`fetching ${url}`);

  const tmpDir = path.join(sidecarDir, ".tmp");
  await rm(tmpDir, { recursive: true, force: true });
  await mkdir(tmpDir, { recursive: true });
  const archive = path.join(tmpDir, `mihomo.${ext}`);
  await download(url, archive);

  if (isWin) {
    execSync(`unzip -o "${archive}" -d "${tmpDir}"`, { stdio: "inherit" });
    const file = readdirSync(tmpDir).find((f) => f.endsWith(".exe"));
    if (!file) throw new Error("exe not found in zip");
    await rename(path.join(tmpDir, file), outPath);
  } else {
    const extracted = path.join(tmpDir, "mihomo");
    await pipeline(createReadStream(archive), createGunzip(), createWriteStream(extracted));
    await rename(extracted, outPath);
    await chmod(outPath, 0o755);
  }

  await copyFile(outPath, plainPath);
  if (!isWin) await chmod(plainPath, 0o755);
  await rm(tmpDir, { recursive: true, force: true });
  console.log(`wrote ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
