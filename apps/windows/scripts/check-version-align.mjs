#!/usr/bin/env node
/**
 * Ensure Windows package versions stay aligned across package.json / Cargo.toml / tauri.conf.json
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function readJson(rel) {
  return JSON.parse(fs.readFileSync(path.join(root, rel), "utf8"));
}

function cargoVersion() {
  const toml = fs.readFileSync(path.join(root, "src-tauri/Cargo.toml"), "utf8");
  const m = toml.match(/^version\s*=\s*"([^"]+)"/m);
  if (!m) throw new Error("Cargo.toml version not found");
  return m[1];
}

const pkg = readJson("package.json").version;
const tauri = readJson("src-tauri/tauri.conf.json").version;
const cargo = cargoVersion();

const versions = { packageJson: pkg, tauriConf: tauri, cargoToml: cargo };
console.log(versions);

const unique = new Set(Object.values(versions));
if (unique.size !== 1) {
  console.error("Windows version mismatch across package.json / tauri.conf.json / Cargo.toml");
  process.exit(1);
}
console.log(`version align OK: ${pkg}`);

// RC.EXE / tauri-winres require a classic ICO 3.00 resource. A PNG renamed to
// .ico fails on Windows runners with "resource file is not in 3.00 format".
const icoPath = path.join(root, "src-tauri/icons/icon.ico");
const ico = fs.readFileSync(icoPath);
if (ico.length >= 8 && ico[0] === 0x89 && ico.subarray(1, 4).toString("ascii") === "PNG") {
  console.error(`${icoPath}: is a PNG, not an ICO (Windows RC.EXE will fail)`);
  process.exit(1);
}
if (
  ico.length < 6 ||
  ico.readUInt16LE(0) !== 0 ||
  ico.readUInt16LE(2) !== 1 ||
  ico.readUInt16LE(4) < 1
) {
  console.error(
    `${icoPath}: missing ICO 3.00 header (reserved=0, type=1, count>=1)`,
  );
  process.exit(1);
}
console.log(
  `icon.ico OK (ICO type=1, ${ico.readUInt16LE(4)} image(s), ${ico.length} bytes)`,
);
