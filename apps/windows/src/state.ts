import type {
  AppNotice,
  AppSection,
  ControllerHealth,
  CoreStatus,
  ExitIpResult,
  LogEntry,
  LogLevel,
  LogSource,
  RoutingMode,
  SpeedTestResult,
  SystemProxyStatus,
  TrafficSnapshot,
  VirtualNetworkStatus,
} from "./types";
import { DEFAULT_PROFILE } from "./types";

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
  core: CoreStatus | null;
  proxy: SystemProxyStatus | null;
  virtualNetwork: VirtualNetworkStatus | null;
  traffic: TrafficSnapshot | null;
  exitIp: ExitIpResult | null;
  controller: ControllerHealth | null;
  runtimeYaml: string;
  speedResults: SpeedTestResult[];
  speedMessage: string;
  busy: {
    start: boolean;
    stop: boolean;
    project: boolean;
    speed: boolean;
    exitIp: boolean;
    health: boolean;
  };
  notice: AppNotice | null;
  logs: LogEntry[];
  logFilter: {
    source: LogSource | "all";
    level: LogLevel | "all";
    query: string;
  };
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
    core: null,
    proxy: null,
    virtualNetwork: null,
    traffic: null,
    exitIp: null,
    controller: null,
    runtimeYaml: "# 在「连接配置」中生成运行配置后显示",
    speedResults: [],
    speedMessage: "需要先执行 pnpm prebuild 下载 CFST",
    busy: {
      start: false,
      stop: false,
      project: false,
      speed: false,
      exitIp: false,
      health: false,
    },
    notice: null,
    logs: [],
    logFilter: { source: "all", level: "all", query: "" },
    bootstrapped: false,
    bootstrapError: null,
  };
}

export function pushLog(
  model: AppModel,
  level: LogLevel,
  source: LogSource,
  message: string,
  max = 500,
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
  return model.logs.filter((entry) => {
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
}

export function sessionPrefsFromModel(model: AppModel) {
  return {
    profileYaml: model.profileYaml,
    selectedAddress: model.selectedAddress,
    routingMode: model.routingMode,
    systemProxyEnabled: model.systemProxyEnabled,
    lastSpeedIpRange: model.speedIpRange,
    disableDownload: model.speedDisableDownload,
  };
}

export function hasUsableProfile(model: AppModel): boolean {
  const yaml = model.profileYaml.trim();
  return yaml.length > 0 && !yaml.includes("origin.example.com");
}

export function configurationReady(model: AppModel): boolean {
  if (model.routingMode === "direct") return true;
  return model.selectedAddress.trim().length > 0 && model.profileYaml.trim().length > 0;
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
