/** Presentation helpers aligned with macOS ByteRateFormatter spirit. */

import type { SpeedTestResult, TrafficPoint } from "./types";

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "—";
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
  return `${value.toFixed(digits)} ${units[unit]}`;
}

export function formatRate(bps: number): string {
  if (!Number.isFinite(bps) || bps < 0) return "—";
  return `${formatBytes(bps)}/s`;
}

export function formatTime(ts: number): string {
  const d = new Date(ts);
  return d.toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

export function isLikelyIPv6(value: string): boolean {
  const v = value.trim();
  if (!v || v.includes(".")) return false;
  return v.includes(":") && /^[0-9a-fA-F:]+$/.test(v);
}

export function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function truncateMiddle(text: string, max = 42): string {
  if (text.length <= max) return text;
  const head = Math.ceil((max - 1) / 2);
  const tail = Math.floor((max - 1) / 2);
  return `${text.slice(0, head)}…${text.slice(-tail)}`;
}

/** Parse CFST-style numeric fields (e.g. "12.3 ms", "1.2 MB/s", "0.00%"). */
export function parseMetricNumber(raw: string): number {
  const m = raw.replace(/,/g, "").match(/-?\d+(?:\.\d+)?/);
  return m ? Number(m[0]) : Number.NaN;
}

export function resultPerformanceSummary(result: SpeedTestResult | undefined): string {
  if (!result) return "";
  const parts = [
    result.latency ? `延迟 ${result.latency}` : "",
    result.loss ? `丢包 ${result.loss}` : "",
    result.speed && result.speed !== "0" ? `速度 ${result.speed}` : "",
    result.region || "",
  ].filter(Boolean);
  return parts.join(" · ");
}

export function sparklinePaths(
  points: TrafficPoint[],
  width: number,
  height: number,
): { up: string; down: string; areaDown: string } {
  if (points.length === 0) {
    return { up: "", down: "", areaDown: "" };
  }
  const max = Math.max(1, ...points.map((p) => Math.max(p.up, p.down)));
  const step = points.length <= 1 ? width : width / (points.length - 1);
  const yOf = (v: number) => height - (v / max) * (height - 4) - 2;
  const coords = (key: "up" | "down") =>
    points.map((p, i) => `${i === 0 ? "M" : "L"}${i * step},${yOf(p[key])}`).join(" ");
  const downPath = coords("down");
  const areaDown =
    points.length > 0
      ? `${downPath} L${(points.length - 1) * step},${height} L0,${height} Z`
      : "";
  return { up: coords("up"), down: downPath, areaDown };
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(ta);
      return ok;
    } catch {
      return false;
    }
  }
}
