import { invoke } from "@tauri-apps/api/core";
import type {
  ControllerHealth,
  CoreStatus,
  ExitIpResult,
  SessionPrefs,
  SpeedTestResponse,
  SystemProxyStatus,
  TrafficSnapshot,
  VirtualNetworkStatus,
} from "./types";

/** Thin Tauri command wrappers. Safe no-ops fail with thrown errors for callers. */

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
}): Promise<string> {
  return invoke<string>("project_runtime_config", args);
}

export async function coreStatus(): Promise<CoreStatus> {
  return invoke<CoreStatus>("core_status");
}

export async function startCore(args: {
  profileYaml: string;
  selectedAddress: string | null;
  routingMode: string;
  enableSystemProxy: boolean;
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

export async function runSpeedTest(request: {
  ipRange: string | null;
  disableDownload: boolean;
  httping: boolean;
  threads: number;
  pingCount: number;
  downloadCount: number;
  downloadTime: number;
  port?: number;
}): Promise<SpeedTestResponse> {
  return invoke<SpeedTestResponse>("run_speed_test", { request });
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
