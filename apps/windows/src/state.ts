import { isLikelyIPv6, parseMetricNumber, resultPerformanceSummary } from "./format";
import type {
  AppNotice,
  AppSection,
  ConfirmDialog,
  ControllerHealth,
  CoreStatus,
  ExitIpMode,
  ExitIpResult,
  LogEntry,
  LogLevel,
  LogSource,
  NodeSortKey,
  ProfileSummary,
  ReadinessIssue,
  RoutingMode,
  SpeedTestParams,
  SpeedTestResult,
  SystemProxyStatus,
  TrafficPoint,
  TrafficSnapshot,
  VirtualNetworkStatus,
} from "./types";
import {
  DEFAULT_PROFILE,
  DEFAULT_SPEED_PARAMS,
  TRAFFIC_HISTORY_LIMIT,
} from "./types";

export type AppModel = {
  section: AppSection;
  version: string;
  profileYaml: string;
  selectedAddress: string;
  routingMode: RoutingMode;
  systemProxyEnabled: boolean;
  virtualNetworkEnabled: boolean;
  speedIpRange: string;
  speedDisableDownload: boolean;
  speedParams: SpeedTestParams;
  showSpeedParams: boolean;
  exitIpMode: ExitIpMode;
  core: CoreStatus | null;
  proxy: SystemProxyStatus | null;
  virtualNetwork: VirtualNetworkStatus | null;
  traffic: TrafficSnapshot | null;
  trafficHistory: TrafficPoint[];
  exitIp: ExitIpResult | null;
  controller: ControllerHealth | null;
  runtimeYaml: string;
  speedResults: SpeedTestResult[];
  speedMessage: string;
  speedResultsAt: number | null;
  nodeSortKey: NodeSortKey;
  nodeSortAsc: boolean;
  selectedResultIp: string | null;
  busy: {
    start: boolean;
    stop: boolean;
    project: boolean;
    speed: boolean;
    exitIp: boolean;
    health: boolean;
    sysProxy: boolean;
  };
  notice: AppNotice | null;
  logs: LogEntry[];
  logFilter: {
    source: LogSource | "all";
    level: LogLevel | "all";
    query: string;
  };
  logNewestFirst: boolean;
  confirm: ConfirmDialog | null;
  bootstrapped: boolean;
  bootstrapError: string | null;
};

let noticeSeq = 0;
let logSeq = 0;

export function createInitialModel(): AppModel {
  return {
    section: "overview",
    version: "—",
    profileYaml: DEFAULT_PROFILE,
    selectedAddress: "2001:db8::1",
    routingMode: "rule",
    systemProxyEnabled: false,
    virtualNetworkEnabled: false,
    speedIpRange: "2606:4700::/32",
    speedDisableDownload: true,
    speedParams: { ...DEFAULT_SPEED_PARAMS },
    showSpeedParams: false,
    exitIpMode: "auto",
    core: null,
    proxy: null,
    virtualNetwork: null,
    traffic: null,
    trafficHistory: [],
    exitIp: null,
    controller: null,
    runtimeYaml: "# 在「连接配置」中生成运行配置后显示",
    speedResults: [],
    speedMessage: "需要先执行 pnpm prebuild 下载 CFST",
    speedResultsAt: null,
    nodeSortKey: "latency",
    nodeSortAsc: true,
    selectedResultIp: null,
    busy: {
      start: false,
      stop: false,
      project: false,
      speed: false,
      exitIp: false,
      health: false,
      sysProxy: false,
    },
    notice: null,
    logs: [],
    logFilter: { source: "all", level: "all", query: "" },
    logNewestFirst: true,
    confirm: null,
    bootstrapped: false,
    bootstrapError: null,
  };
}

export function pushLog(
  model: AppModel,
  level: LogLevel,
  source: LogSource,
  message: string,
  max = 800,
): void {
  logSeq += 1;
  model.logs.push({
    id: `log-${logSeq}`,
    at: Date.now(),
    level,
    source,
    message,
  });
  if (model.logs.length > max) {
    model.logs.splice(0, model.logs.length - max);
  }
}

export function showNotice(
  model: AppModel,
  message: string,
  style: AppNotice["style"] = "info",
  action?: AppNotice["action"],
): void {
  noticeSeq += 1;
  model.notice = { id: noticeSeq, message, style, action };
}

export function clearNotice(model: AppModel): void {
  model.notice = null;
}

export function filteredLogs(model: AppModel): LogEntry[] {
  const q = model.logFilter.query.trim().toLowerCase();
  const list = model.logs.filter((entry) => {
    if (model.logFilter.source !== "all" && entry.source !== model.logFilter.source) {
      return false;
    }
    if (model.logFilter.level !== "all" && entry.level !== model.logFilter.level) {
      return false;
    }
    if (q && !entry.message.toLowerCase().includes(q)) {
      return false;
    }
    return true;
  });
  return model.logNewestFirst ? list.slice().reverse() : list;
}

export function sessionPrefsFromModel(model: AppModel) {
  return {
    profileYaml: model.profileYaml,
    selectedAddress: model.selectedAddress,
    routingMode: model.routingMode,
    systemProxyEnabled: model.systemProxyEnabled,
    lastSpeedIpRange: model.speedIpRange,
    disableDownload: model.speedDisableDownload,
    speedThreads: model.speedParams.threads,
    speedPingCount: model.speedParams.pingCount,
    speedDownloadCount: model.speedParams.downloadCount,
    speedDownloadTime: model.speedParams.downloadTime,
    speedHttping: model.speedParams.httping,
    speedPort: model.speedParams.port,
    exitIpMode: model.exitIpMode,
    lastSection: model.section,
  };
}

export function hasUsableProfile(model: AppModel): boolean {
  const yaml = model.profileYaml.trim();
  return yaml.length > 0 && !yaml.includes("origin.example.com");
}

export function configurationReady(model: AppModel): boolean {
  return readinessIssues(model).length === 0;
}

export function routingModeLabel(mode: RoutingMode): string {
  switch (mode) {
    case "rule":
      return "规则";
    case "global":
      return "全局";
    case "direct":
      return "直连";
  }
}

export function parseProfileSummary(yaml: string): ProfileSummary {
  const text = yaml ?? "";
  const notes: string[] = [];
  const proxyBlocks = text.split(/\n(?= {2}- name:)/).filter((b) => /type:\s*\S+/.test(b));
  // Prefer list items under proxies:
  const nameMatches = [...text.matchAll(/^\s{2,}-\s+name:\s*(.+)$/gm)].map((m) =>
    m[1].trim().replace(/^["']|["']$/g, ""),
  );
  const typeMatches = [...text.matchAll(/^\s+type:\s*(\S+)/gm)].map((m) => m[1].trim());
  const proxyCount = Math.max(nameMatches.length, proxyBlocks.length);
  const primaryName = nameMatches[0] ?? null;
  const primaryType = typeMatches[0] ?? null;
  const hasXviasix = /x-viasix\s*:/.test(text);
  const looksLikeExample =
    /example\.com|11111111-1111-4111-1111-111111111111|origin\.example/.test(text);
  const hasInlineProxy = proxyCount > 0;

  if (!text.trim()) notes.push("配置为空");
  if (!hasInlineProxy) notes.push("未检测到内联代理（Provider-only 会被拒绝）");
  if (looksLikeExample) notes.push("仍为示例配置，请替换为真实入口");
  if (!hasXviasix) notes.push("建议保留 x-viasix.primary-server: selected-ip");
  if (proxyCount > 1) notes.push(`检测到 ${proxyCount} 个代理，运行时只保留第一个可注入项`);

  return {
    primaryName,
    primaryType,
    proxyCount,
    hasXviasix,
    looksLikeExample,
    hasInlineProxy,
    notes,
  };
}

export function readinessIssues(model: AppModel): ReadinessIssue[] {
  const issues: ReadinessIssue[] = [];
  if (model.routingMode !== "direct") {
    const summary = parseProfileSummary(model.profileYaml);
    if (!summary.hasInlineProxy) {
      issues.push({
        code: "profile",
        message: "连接配置需要包含可注入 server 的内联代理",
        action: "gotoProfiles",
      });
    } else if (summary.looksLikeExample) {
      issues.push({
        code: "profile",
        message: "连接配置仍是示例内容，请导入真实 Profile",
        action: "gotoProfiles",
      });
    }
    if (!isLikelyIPv6(model.selectedAddress)) {
      issues.push({
        code: "node",
        message: "请先选择有效的 IPv6 入口地址",
        action: "gotoNodes",
      });
    }
  }
  const virt = model.virtualNetwork;
  if (virt?.enabled && !virt.available) {
    issues.push({
      code: "network",
      message: "已请求虚拟网卡，但 Wintun 不可用",
      action: "openSettings",
    });
  }
  return issues;
}

export function canStartProxy(model: AppModel): boolean {
  if (model.busy.start || model.busy.stop) return false;
  if (model.core?.running) return false;
  return readinessIssues(model).length === 0;
}

export function selectedNodeResult(model: AppModel): SpeedTestResult | undefined {
  return model.speedResults.find((r) => r.ip === model.selectedAddress);
}

export function selectedNodeSecondary(model: AppModel): string {
  const result = selectedNodeResult(model);
  if (result) return resultPerformanceSummary(result);
  return isLikelyIPv6(model.selectedAddress)
    ? "已选择入口，可在首页检测出口或启动连接"
    : "请先选择有效 IPv6 入口";
}

export function sortedSpeedResults(model: AppModel): SpeedTestResult[] {
  const key = model.nodeSortKey;
  const dir = model.nodeSortAsc ? 1 : -1;
  const list = model.speedResults.slice();
  list.sort((a, b) => {
    const av = sortValue(a, key);
    const bv = sortValue(b, key);
    if (typeof av === "string" && typeof bv === "string") {
      return av.localeCompare(bv, "zh-CN") * dir;
    }
    const an = Number(av);
    const bn = Number(bv);
    if (Number.isNaN(an) && Number.isNaN(bn)) return 0;
    if (Number.isNaN(an)) return 1;
    if (Number.isNaN(bn)) return -1;
    return (an - bn) * dir;
  });
  return list;
}

function sortValue(row: SpeedTestResult, key: NodeSortKey): string | number {
  switch (key) {
    case "ip":
      return row.ip;
    case "region":
      return row.region || "";
    case "sent":
      return parseMetricNumber(row.sent);
    case "received":
      return parseMetricNumber(row.received);
    case "loss":
      return parseMetricNumber(row.loss);
    case "latency":
      return parseMetricNumber(row.latency);
    case "speed":
      return parseMetricNumber(row.speed);
  }
}

export function pushTrafficSample(model: AppModel, snap: TrafficSnapshot): void {
  if (!snap.live) return;
  model.trafficHistory.push({
    at: Date.now(),
    up: snap.upBps,
    down: snap.downBps,
  });
  if (model.trafficHistory.length > TRAFFIC_HISTORY_LIMIT) {
    model.trafficHistory.splice(0, model.trafficHistory.length - TRAFFIC_HISTORY_LIMIT);
  }
}

export function clearTrafficHistory(model: AppModel): void {
  model.trafficHistory = [];
}

export function exitIpEndpoints(mode: ExitIpMode): string[] | null {
  switch (mode) {
    case "ipv4":
      return ["https://api.ipify.org?format=json", "https://api4.ipify.org?format=json"];
    case "ipv6":
      return ["https://api6.ipify.org?format=json", "https://api64.ipify.org?format=json"];
    case "auto":
      return null;
  }
}

export function speedResultsFresh(model: AppModel, maxAgeMs = 30 * 60 * 1000): boolean {
  if (!model.speedResultsAt || model.speedResults.length === 0) return false;
  return Date.now() - model.speedResultsAt < maxAgeMs;
}
