import { invoke } from "@tauri-apps/api/core";
import type {
  ActivityEntry,
  BackendProfileSummary,
  ConnectivityResult,
  ControllerHealth,
  CoreStatus,
  ExitIpResult,
  IpPreset,
  SessionPrefs,
  SpeedTestResponse,
  SystemProxyStatus,
  TrafficSnapshot,
  VirtualNetworkStatus,
} from "./types";

export async function appVersion(): Promise<string> {
  return invoke<string>("app_version");
}

export async function loadSessionPrefs(): Promise<SessionPrefs> {
  return invoke<SessionPrefs>("load_session_prefs");
}

export async function saveSessionPrefs(prefs: SessionPrefs): Promise<void> {
  await invoke("save_session_prefs", { prefs });
}

export async function projectRuntimeConfig(args: {
  profileYaml: string;
  selectedAddress: string | null;
  routingMode: string;
  mixedPort?: number | null;
  controllerPort?: number | null;
  udpEnabled?: boolean | null;
  sniffingEnabled?: boolean | null;
}): Promise<string> {
  return invoke<string>("project_runtime_config", args);
}

export async function summarizeProfile(profileYaml: string): Promise<BackendProfileSummary> {
  return invoke<BackendProfileSummary>("summarize_profile", { profileYaml });
}

export async function readTextFile(path: string): Promise<string> {
  return invoke<string>("read_text_file", { path });
}

export async function coreStatus(): Promise<CoreStatus> {
  return invoke<CoreStatus>("core_status");
}

export async function startCore(args: {
  profileYaml: string;
  selectedAddress: string | null;
  routingMode: string;
  enableSystemProxy: boolean;
  mixedPort?: number | null;
  controllerPort?: number | null;
  tunStack?: string | null;
  tunMtu?: number | null;
  udpEnabled?: boolean | null;
  sniffingEnabled?: boolean | null;
}): Promise<CoreStatus> {
  return invoke<CoreStatus>("start_core", args);
}

export async function stopCore(): Promise<CoreStatus> {
  return invoke<CoreStatus>("stop_core");
}

export async function systemProxyStatus(): Promise<SystemProxyStatus> {
  return invoke<SystemProxyStatus>("system_proxy_status");
}

export async function setSystemProxy(args: {
  enabled: boolean;
  host?: string;
  port?: number;
}): Promise<SystemProxyStatus> {
  return invoke<SystemProxyStatus>("set_system_proxy", args);
}

export async function detectExitIp(endpoints?: string[] | null): Promise<ExitIpResult> {
  return invoke<ExitIpResult>("detect_exit_ip", {
    endpoints: endpoints && endpoints.length > 0 ? endpoints : null,
  });
}

export async function runSpeedTest(
  request: {
    ipRange: string | null;
    disableDownload: boolean;
    httping: boolean;
    threads: number;
    pingCount: number;
    downloadCount: number;
    downloadTime: number;
    port?: number;
  },
  useBundledList = false,
): Promise<SpeedTestResponse> {
  return invoke<SpeedTestResponse>("run_speed_test", {
    request,
    useBundledList,
  });
}

export async function stopSpeedTest(): Promise<boolean> {
  return invoke<boolean>("stop_speed_test");
}

export async function speedTestRunning(): Promise<boolean> {
  return invoke<boolean>("speed_test_running");
}

export async function testCurrentNode(args: {
  selectedAddress: string;
  disableDownload?: boolean;
  threads?: number;
  pingCount?: number;
  port?: number;
}): Promise<SpeedTestResponse> {
  return invoke<SpeedTestResponse>("test_current_node", args);
}

export async function listIpPresets(): Promise<IpPreset[]> {
  return invoke<IpPreset[]>("list_ip_presets");
}

export async function probeConnectivity(args: {
  mixedPort?: number;
  url?: string | null;
}): Promise<ConnectivityResult> {
  return invoke<ConnectivityResult>("probe_connectivity", args);
}

export async function tailCoreLog(maxLines = 200): Promise<string> {
  return invoke<string>("tail_core_log", { maxLines });
}

export async function ensureIpv6List(): Promise<string> {
  return invoke<string>("ensure_ipv6_list");
}

export async function resetIpv6List(): Promise<string> {
  return invoke<string>("reset_ipv6_list");
}

export async function readIpv6List(): Promise<string> {
  return invoke<string>("read_ipv6_list");
}

export async function loadProfileFile(): Promise<string | null> {
  return invoke<string | null>("load_profile_file");
}

export async function saveProfileFile(profileYaml: string): Promise<string> {
  return invoke<string>("save_profile_file", { profileYaml });
}

export async function probeController(): Promise<ControllerHealth> {
  return invoke<ControllerHealth>("probe_controller");
}

export async function sampleTraffic(): Promise<TrafficSnapshot> {
  return invoke<TrafficSnapshot>("sample_traffic");
}

export async function virtualNetworkStatus(): Promise<VirtualNetworkStatus> {
  return invoke<VirtualNetworkStatus>("virtual_network_status");
}

export async function setVirtualNetwork(enabled: boolean): Promise<VirtualNetworkStatus> {
  return invoke<VirtualNetworkStatus>("set_virtual_network", { enabled });
}

export async function listActivityLogs(): Promise<ActivityEntry[]> {
  return invoke<ActivityEntry[]>("list_activity_logs");
}

export async function clearActivityLogs(): Promise<void> {
  await invoke("clear_activity_logs");
}

export async function dataDirPath(): Promise<string> {
  return invoke<string>("data_dir_path");
}

export async function openDataDir(): Promise<string> {
  return invoke<string>("open_data_dir");
}
