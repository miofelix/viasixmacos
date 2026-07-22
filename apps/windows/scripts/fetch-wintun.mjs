#!/usr/bin/env node
/**
 * Download Wintun DLL into src-tauri/sidecar/ for Mihomo TUN on Windows.
 * No-op on non-Windows hosts unless a windows target triple is passed.
 *
 * Usage:
 *   node scripts/fetch-wintun.mjs
 *   node scripts/fetch-wintun.mjs x86_64-pc-windows-msvc
 *   node scripts/fetch-wintun.mjs --force
 */
import { createWriteStream, readdirSync } from "node:fs";
import { access, copyFile, mkdir, rm } from "node:fs/promises";
import { pipeline } from "node:stream/promises";
import { execSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Readable } from "node:stream";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, "..");
const sidecarDir = path.join(appRoot, "src-tauri", "sidecar");
const FORCE = process.argv.includes("--force") || process.argv.includes("-f");
const WINTUN_URL = "https://www.wintun.net/builds/wintun-0.14.1.zip";

const args = process.argv.slice(2).filter((a) => a !== "--force" && a !== "-f");
const targetArg = args[0];
const triple =
  targetArg ||
  (() => {
    try {
      return execSync("rustc -vV", { encoding: "utf8" }).match(/host: (.+)/)?.[1];
    } catch {
      return process.platform === "win32" ? "x86_64-pc-windows-msvc" : "";
    }
  })();

const isWindowsTarget =
  String(triple).includes("windows") || process.platform === "win32";

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

function pickArchDir(triple) {
  if (String(triple).includes("aarch64") || String(triple).includes("arm64")) {
    return "arm64";
  }
  return "amd64";
}

async function main() {
  if (!isWindowsTarget) {
    console.log("skip fetch-wintun (not a Windows target)");
    return;
  }

  await mkdir(sidecarDir, { recursive: true });
  const out = path.join(sidecarDir, "wintun.dll");
  if (!FORCE && (await exists(out))) {
    console.log(`already present: ${out}`);
    return;
  }

  console.log(`fetching ${WINTUN_URL}`);
  const tmpDir = path.join(sidecarDir, ".tmp-wintun");
  await rm(tmpDir, { recursive: true, force: true });
  await mkdir(tmpDir, { recursive: true });
  const zipPath = path.join(tmpDir, "wintun.zip");
  await download(WINTUN_URL, zipPath);

  // unzip works on macOS/Linux CI and Git Bash; on PowerShell use Expand-Archive fallback.
  try {
    execSync(`unzip -o "${zipPath}" -d "${tmpDir}"`, { stdio: "inherit" });
  } catch {
    execSync(
      `powershell -NoProfile -Command "Expand-Archive -Force '${zipPath}' '${tmpDir}'"`,
      { stdio: "inherit" },
    );
  }

  const arch = pickArchDir(triple);
  // Layout: wintun/bin/amd64/wintun.dll or bin/amd64/wintun.dll
  const candidates = [
    path.join(tmpDir, "wintun", "bin", arch, "wintun.dll"),
    path.join(tmpDir, "bin", arch, "wintun.dll"),
  ];
  let src = candidates.find((p) => {
    try {
      readdirSync(path.dirname(p));
      return true;
    } catch {
      return false;
    }
  });
  // brute search
  if (!src) {
    const stack = [tmpDir];
    while (stack.length) {
      const dir = stack.pop();
      for (const name of readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, name.name);
        if (name.isDirectory()) stack.push(full);
        else if (name.name.toLowerCase() === "wintun.dll" && full.includes(arch)) {
          src = full;
          break;
        }
      }
      if (src) break;
    }
  }
  if (!src) throw new Error(`wintun.dll (${arch}) not found in archive`);
  await copyFile(src, out);
  await rm(tmpDir, { recursive: true, force: true });
  console.log(`wrote ${out}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
