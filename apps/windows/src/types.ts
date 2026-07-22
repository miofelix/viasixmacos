/** Shared domain types for the Windows shell (mirrors macOS product surface). */

export type AppSection = "overview" | "nodes" | "profiles" | "logs" | "settings";

export type RoutingMode = "rule" | "global" | "direct";

export type ExitIpMode = "auto" | "ipv4" | "ipv6";

export type NodeSortKey =
  | "ip"
  | "sent"
  | "received"
  | "loss"
  | "latency"
  | "speed"
  | "region";

export type CoreStatus = {
  running: boolean;
  pid: number | null;
  message: string;
  controllerPort: number | null;
};

export type ControllerHealth = {
  ok: boolean;
  endpoint: string;
  message: string;
  version: string | null;
};

export type VirtualNetworkStatus = {
  available: boolean;
  enabled: boolean;
  backend: string;
  message: string;
  wintunPath: string | null;
};

export type TrafficSnapshot = {
  live: boolean;
  upBps: number;
  downBps: number;
  uploadTotal: number;
  downloadTotal: number;
  message: string;
};

export type TrafficPoint = {
  at: number;
  up: number;
  down: number;
};

export type SystemProxyStatus = {
  enabled: boolean;
  managedByViasix: boolean;
  endpoint: { host: string; port: number } | null;
  message: string;
};

export type ExitIpResult = {
  ip: string;
  family: string;
  source: string;
  message: string;
};

export type SpeedTestResult = {
  ip: string;
  sent: string;
  received: string;
  loss: string;
  latency: string;
  speed: string;
  region: string;
};

export type SpeedTestResponse = {
  results: SpeedTestResult[];
  message: string;
  resultCsvPath: string;
};

export type SpeedTestParams = {
  threads: number;
  pingCount: number;
  downloadCount: number;
  downloadTime: number;
  httping: boolean;
  port: number;
};

export type SessionPrefs = {
  profileYaml: string;
  selectedAddress: string;
  routingMode: string;
  systemProxyEnabled: boolean;
  lastSpeedIpRange: string;
  disableDownload: boolean;
  speedThreads?: number | null;
  speedPingCount?: number | null;
  speedDownloadCount?: number | null;
  speedDownloadTime?: number | null;
  speedHttping?: boolean | null;
  speedPort?: number | null;
  exitIpMode?: string | null;
  lastSection?: string | null;
};

export type NoticeStyle = "info" | "success" | "error";

export type AppNotice = {
  id: number;
  message: string;
  style: NoticeStyle;
  action?: "openSettings" | "gotoNodes" | "gotoProfiles";
};

export type LogLevel = "info" | "success" | "warn" | "error";
export type LogSource = "app" | "core" | "proxy" | "speed" | "network" | "config";

export type LogEntry = {
  id: string;
  at: number;
  level: LogLevel;
  source: LogSource;
  message: string;
};

export type ProfileSummary = {
  primaryName: string | null;
  primaryType: string | null;
  proxyCount: number;
  hasXviasix: boolean;
  looksLikeExample: boolean;
  hasInlineProxy: boolean;
  notes: string[];
};

export type ReadinessIssue = {
  code: "profile" | "node" | "network" | "runtime";
  message: string;
  action?: AppNotice["action"];
};

export type ConfirmDialog = {
  title: string;
  message: string;
  confirmLabel: string;
  /** When confirmed, select this IP (and optionally reconnect). */
  selectIp?: string;
  reconnect?: boolean;
};

export type SectionMeta = {
  id: AppSection;
  title: string;
  subtitle: string;
  icon: string;
};

export const SECTIONS: SectionMeta[] = [
  {
    id: "overview",
    title: "首页",
    subtitle: "IPv6 链路状态与控制",
    icon: "home",
  },
  {
    id: "nodes",
    title: "IPv6 优选",
    subtitle: "测速并选择 IPv6 地址",
    icon: "nodes",
  },
  {
    id: "profiles",
    title: "连接配置",
    subtitle: "管理 IPv6 代理入口配置",
    icon: "profile",
  },
  {
    id: "logs",
    title: "日志",
    subtitle: "查看代理与测速活动",
    icon: "logs",
  },
  {
    id: "settings",
    title: "设置",
    subtitle: "服务器、本机与应用设置",
    icon: "settings",
  },
];

export const DEFAULT_PROFILE = `proxies:
  - name: My VLESS
    type: vless
    server: origin.example.com
    port: 443
    uuid: 11111111-1111-4111-1111-111111111111
    network: ws
    tls: true
    servername: origin.example.com
    ws-opts:
      path: /proxy
      headers:
        Host: origin.example.com
x-viasix:
  version: 1
  primary-server: selected-ip
`;

export const DEFAULT_SPEED_PARAMS: SpeedTestParams = {
  threads: 100,
  pingCount: 4,
  downloadCount: 5,
  downloadTime: 5,
  httping: true,
  port: 443,
};

export const ROUTING_MODES: {
  id: RoutingMode;
  title: string;
  description: string;
}[] = [
  {
    id: "rule",
    title: "规则",
    description: "私有地址直连，其余流量通过代理。",
  },
  {
    id: "global",
    title: "全局",
    description: "所有经过本地代理的流量都通过代理节点。",
  },
  {
    id: "direct",
    title: "直连",
    description: "所有经过本地代理的流量都直接连接。",
  },
];

export const TRAFFIC_HISTORY_LIMIT = 90;
