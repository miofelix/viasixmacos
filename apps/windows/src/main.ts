import "./styles.css";
import * as api from "./api";
import { formatBytes, formatRate } from "./format";
import {
  clearNotice,
  createInitialModel,
  pushLog,
  sessionPrefsFromModel,
  showNotice,
  type AppModel,
} from "./state";
import type { AppSection, RoutingMode } from "./types";
import { renderSection, renderShell, syncChrome } from "./views";

const rootEl = document.querySelector<HTMLDivElement>("#app");
if (!rootEl) {
  throw new Error("#app missing");
}
const root: HTMLDivElement = rootEl;

const model: AppModel = createInitialModel();
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let trafficTimer: ReturnType<typeof setInterval> | null = null;
let noticeTimer: ReturnType<typeof setTimeout> | null = null;

root.innerHTML = renderShell();
const detail = document.querySelector<HTMLDivElement>("#detail-content")!;

function scheduleSavePrefs(): void {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    void api.saveSessionPrefs(sessionPrefsFromModel(model)).catch(() => {
      // ignore when not running inside Tauri
    });
  }, 400);
}

function toast(
  message: string,
  style: "info" | "success" | "error" = "info",
  action?: "openSettings",
): void {
  showNotice(model, message, style, action);
  if (noticeTimer) clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => {
    clearNotice(model);
    syncChrome(model);
  }, 5200);
  syncChrome(model);
}

function paint(options?: { preserveFocus?: boolean }): void {
  const active = document.activeElement as HTMLElement | null;
  const focusId = options?.preserveFocus && active?.id ? active.id : null;
  const selection =
    focusId && active instanceof HTMLInputElement
      ? { start: active.selectionStart, end: active.selectionEnd }
      : null;

  detail.innerHTML = renderSection(model);
  syncChrome(model);
  bindSectionControls();

  if (focusId) {
    const el = document.getElementById(focusId) as HTMLInputElement | HTMLTextAreaElement | null;
    if (el) {
      el.focus();
      if (selection && "setSelectionRange" in el && selection.start != null && selection.end != null) {
        try {
          el.setSelectionRange(selection.start, selection.end);
        } catch {
          // ignore for non-text inputs
        }
      }
    }
  }
}

function navigate(section: AppSection): void {
  if (model.section === section) return;
  model.section = section;
  paint();
}

function bindShell(): void {
  document.querySelectorAll<HTMLButtonElement>(".nav-item").forEach((btn) => {
    btn.addEventListener("click", () => {
      const section = btn.dataset.section as AppSection;
      navigate(section);
    });
  });

  // Global delegated actions (notice host + section buttons).
  root.addEventListener("click", (event) => {
    const target = (event.target as HTMLElement).closest<HTMLElement>("[data-action]");
    if (!target) return;
    const action = target.dataset.action;
    if (!action) return;
    void handleAction(action, target);
  });
}

function bindSectionControls(): void {
  const speedIp = document.querySelector<HTMLInputElement>("#speed-ip");
  const speedDd = document.querySelector<HTMLInputElement>("#speed-dd");
  if (speedIp) {
    speedIp.addEventListener("input", () => {
      model.speedIpRange = speedIp.value;
      scheduleSavePrefs();
    });
  }
  if (speedDd) {
    speedDd.addEventListener("change", () => {
      model.speedDisableDownload = speedDd.checked;
      scheduleSavePrefs();
    });
  }

  const profileYaml = document.querySelector<HTMLTextAreaElement>("#profile-yaml");
  const profileIp = document.querySelector<HTMLInputElement>("#profile-selected-ip");
  const profileMode = document.querySelector<HTMLSelectElement>("#profile-mode");
  if (profileYaml) {
    profileYaml.addEventListener("input", () => {
      model.profileYaml = profileYaml.value;
      scheduleSavePrefs();
    });
  }
  if (profileIp) {
    profileIp.addEventListener("input", () => {
      model.selectedAddress = profileIp.value.trim();
      scheduleSavePrefs();
      syncChrome(model);
    });
  }
  if (profileMode) {
    profileMode.addEventListener("change", () => {
      model.routingMode = profileMode.value as RoutingMode;
      scheduleSavePrefs();
      paint({ preserveFocus: true });
    });
  }

  document.querySelectorAll<HTMLButtonElement>("[data-routing]").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (model.core?.running) {
        toast("请先断开连接再切换代理模式", "error");
        return;
      }
      const mode = btn.dataset.routing as RoutingMode;
      model.routingMode = mode;
      scheduleSavePrefs();
      pushLog(model, "info", "config", `代理模式切换为 ${mode}`);
      paint();
    });
  });

  const sysProxy = document.querySelector<HTMLInputElement>("#toggle-sys-proxy");
  if (sysProxy) {
    sysProxy.addEventListener("change", () => {
      model.systemProxyEnabled = sysProxy.checked;
      scheduleSavePrefs();
      pushLog(
        model,
        "info",
        "proxy",
        model.systemProxyEnabled ? "已勾选启动时启用系统代理" : "已取消启动时启用系统代理",
      );
    });
  }

  for (const id of ["#toggle-virt-net", "#settings-virt-net"] as const) {
    const el = document.querySelector<HTMLInputElement>(id);
    if (!el) continue;
    el.addEventListener("change", () => {
      void setVirtualNetwork(el.checked);
    });
  }

  document.querySelectorAll<HTMLButtonElement>("[data-select-ip]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const ip = btn.dataset.selectIp ?? "";
      model.selectedAddress = ip;
      scheduleSavePrefs();
      pushLog(model, "success", "speed", `已选择节点 ${ip}`);
      toast(`已选择节点 ${ip}`, "success");
      paint();
    });
  });

  const logQuery = document.querySelector<HTMLInputElement>("#log-query");
  const logSource = document.querySelector<HTMLSelectElement>("#log-source");
  const logLevel = document.querySelector<HTMLSelectElement>("#log-level");
  if (logQuery) {
    logQuery.addEventListener("input", () => {
      model.logFilter.query = logQuery.value;
      paint({ preserveFocus: true });
    });
  }
  if (logSource) {
    logSource.addEventListener("change", () => {
      model.logFilter.source = logSource.value as AppModel["logFilter"]["source"];
      paint();
    });
  }
  if (logLevel) {
    logLevel.addEventListener("change", () => {
      model.logFilter.level = logLevel.value as AppModel["logFilter"]["level"];
      paint();
    });
  }
}

async function handleAction(action: string, _el: HTMLElement): Promise<void> {
  switch (action) {
    case "goto-nodes":
      navigate("nodes");
      return;
    case "goto-profiles":
      navigate("profiles");
      return;
    case "goto-settings":
      navigate("settings");
      return;
    case "dismiss-notice":
      clearNotice(model);
      syncChrome(model);
      return;
    case "start-core":
      await startCore();
      return;
    case "stop-core":
      await stopCore();
      return;
    case "project-config":
      await projectConfig();
      return;
    case "run-speed":
      await runSpeed();
      return;
    case "apply-best":
      applyBest();
      return;
    case "detect-exit":
      await detectExit();
      return;
    case "probe-controller":
      await probeController();
      return;
    case "refresh-status":
      await refreshAllStatus();
      paint();
      toast("状态已刷新", "info");
      return;
    case "apply-sys-proxy":
      await applySystemProxy(true);
      return;
    case "clear-sys-proxy":
      await applySystemProxy(false);
      return;
    case "clear-logs":
      model.logs = [];
      paint();
      return;
    default:
      return;
  }
}

async function setVirtualNetwork(enabled: boolean): Promise<void> {
  try {
    const status = await api.setVirtualNetwork(enabled);
    model.virtualNetwork = status;
    model.virtualNetworkEnabled = status.enabled;
    pushLog(model, "info", "network", status.message);
    if (status.enabled) {
      toast("已请求 TUN：请重新启动 Mihomo 以应用（通常需管理员）", "info");
    } else {
      toast("已关闭虚拟网卡请求", "info");
    }
    paint();
  } catch (error) {
    model.virtualNetworkEnabled = false;
    pushLog(model, "error", "network", `虚拟网卡切换失败：${error}`);
    toast(`虚拟网卡切换失败：${error}`, "error", "openSettings");
    paint();
  }
}

async function projectConfig(): Promise<void> {
  model.busy.project = true;
  paint();
  try {
    const mode = model.routingMode;
    const yaml = await api.projectRuntimeConfig({
      profileYaml: model.profileYaml,
      selectedAddress: mode === "direct" ? null : model.selectedAddress || null,
      routingMode: mode,
    });
    model.runtimeYaml = yaml;
    pushLog(model, "success", "config", "运行配置投影成功");
    toast("投影成功", "success");
    scheduleSavePrefs();
  } catch (error) {
    model.runtimeYaml = String(error);
    pushLog(model, "error", "config", `投影失败：${error}`);
    toast(`投影失败：${error}`, "error");
  } finally {
    model.busy.project = false;
    paint();
  }
}

async function startCore(): Promise<void> {
  model.busy.start = true;
  paint();
  try {
    const mode = model.routingMode;
    const status = await api.startCore({
      profileYaml: model.profileYaml,
      selectedAddress: mode === "direct" ? null : model.selectedAddress || null,
      routingMode: mode,
      enableSystemProxy: model.systemProxyEnabled,
    });
    model.core = status;
    pushLog(model, status.running ? "success" : "warn", "core", status.message);
    toast(status.message, status.running ? "success" : "error");
    await refreshProxyStatus();
    if (status.running) startTrafficPolling();
  } catch (error) {
    pushLog(model, "error", "core", `启动失败：${error}`);
    toast(`启动失败：${error}`, "error");
  } finally {
    model.busy.start = false;
    paint();
  }
}

async function stopCore(): Promise<void> {
  model.busy.stop = true;
  paint();
  try {
    const status = await api.stopCore();
    model.core = status;
    stopTrafficPolling();
    pushLog(model, "info", "core", status.message);
    toast(status.message, "info");
    await refreshProxyStatus();
  } catch (error) {
    pushLog(model, "error", "core", `停止失败：${error}`);
    toast(`停止失败：${error}`, "error");
  } finally {
    model.busy.stop = false;
    paint();
  }
}

async function applySystemProxy(enabled: boolean): Promise<void> {
  try {
    const status = await api.setSystemProxy({
      enabled,
      host: "127.0.0.1",
      port: 11451,
    });
    model.proxy = status;
    model.systemProxyEnabled = enabled && status.enabled;
    scheduleSavePrefs();
    pushLog(model, "info", "proxy", status.message);
    toast(status.message, "success");
    paint();
  } catch (error) {
    pushLog(model, "error", "proxy", `系统代理操作失败：${error}`);
    toast(`系统代理操作失败：${error}`, "error");
  }
}

async function detectExit(): Promise<void> {
  model.busy.exitIp = true;
  paint();
  try {
    const result = await api.detectExitIp();
    model.exitIp = result;
    pushLog(model, "success", "network", `${result.message}（来源 ${result.source}）`);
    toast(`出口 ${result.ip}`, "success");
  } catch (error) {
    pushLog(model, "error", "network", `出口检测失败：${error}`);
    toast(`出口检测失败：${error}`, "error");
  } finally {
    model.busy.exitIp = false;
    paint();
  }
}

async function probeController(): Promise<void> {
  model.busy.health = true;
  paint();
  try {
    const health = await api.probeController();
    model.controller = health;
    pushLog(model, health.ok ? "success" : "warn", "core", health.message);
    toast(health.message, health.ok ? "success" : "error");
  } catch (error) {
    pushLog(model, "error", "core", `探测失败：${error}`);
    toast(`探测失败：${error}`, "error");
  } finally {
    model.busy.health = false;
    paint();
  }
}

async function runSpeed(): Promise<void> {
  model.busy.speed = true;
  model.speedMessage = "测速进行中，请稍候…";
  paint();
  try {
    const response = await api.runSpeedTest({
      ipRange: model.speedIpRange.trim() || null,
      disableDownload: model.speedDisableDownload,
      httping: true,
      threads: 100,
      pingCount: 4,
      downloadCount: 5,
      downloadTime: 5,
    });
    model.speedResults = response.results;
    model.speedMessage = response.message;
    pushLog(model, "success", "speed", response.message);
    scheduleSavePrefs();
    toast(response.message, "success");
  } catch (error) {
    model.speedMessage = `测速失败：${error}`;
    pushLog(model, "error", "speed", model.speedMessage);
    toast(model.speedMessage, "error");
  } finally {
    model.busy.speed = false;
    paint();
  }
}

function applyBest(): void {
  if (model.speedResults.length === 0) {
    toast("没有可应用的测速结果", "error");
    return;
  }
  model.selectedAddress = model.speedResults[0].ip;
  model.speedMessage = `已应用最佳结果：${model.selectedAddress}`;
  scheduleSavePrefs();
  pushLog(model, "success", "speed", model.speedMessage);
  toast(model.speedMessage, "success");
  paint();
}

async function refreshCoreStatus(): Promise<void> {
  try {
    model.core = await api.coreStatus();
  } catch {
    // browser preview
  }
}

async function refreshProxyStatus(): Promise<void> {
  try {
    model.proxy = await api.systemProxyStatus();
    if (model.proxy.managedByViasix) {
      model.systemProxyEnabled = model.proxy.enabled;
    }
  } catch (error) {
    pushLog(model, "warn", "proxy", `系统代理状态不可用：${error}`);
  }
}

async function refreshVirtualNetwork(): Promise<void> {
  try {
    model.virtualNetwork = await api.virtualNetworkStatus();
    model.virtualNetworkEnabled = model.virtualNetwork.enabled;
  } catch (error) {
    pushLog(model, "warn", "network", `虚拟网卡状态不可用：${error}`);
  }
}

async function refreshTraffic(): Promise<void> {
  try {
    model.traffic = await api.sampleTraffic();
    // Soft-update metric tiles on overview to avoid full repaint thrash.
    if (model.section === "overview") {
      patchOverviewTraffic();
    }
  } catch {
    model.traffic = null;
  }
}

function patchOverviewTraffic(): void {
  const traffic = model.traffic;
  if (!traffic) return;
  const running = !!model.core?.running;
  const grid = detail.querySelector(".metric-grid");
  if (!grid) return;
  const values = grid.querySelectorAll(".metric-value");
  if (values.length < 6) return;
  values[0].textContent = traffic.live ? formatRate(traffic.upBps) : "—";
  values[1].textContent = traffic.live ? formatRate(traffic.downBps) : "—";
  values[2].textContent = running
    ? traffic.live
      ? "实时采集"
      : "连接中"
    : "未连接";
  values[3].textContent = formatBytes(traffic.uploadTotal);
  values[4].textContent = formatBytes(traffic.downloadTotal);
  const help = detail.querySelector(".metric-grid + .help-text");
  if (help) {
    help.textContent =
      traffic.message ||
      (running ? "正在采样 /connections" : "启动代理后显示实时上下行速率");
  }
}

function startTrafficPolling(): void {
  if (trafficTimer) return;
  void refreshTraffic();
  trafficTimer = setInterval(() => {
    void refreshTraffic();
  }, 1500);
}

function stopTrafficPolling(): void {
  if (trafficTimer) {
    clearInterval(trafficTimer);
    trafficTimer = null;
  }
  model.traffic = null;
}

async function refreshAllStatus(): Promise<void> {
  await Promise.all([refreshCoreStatus(), refreshProxyStatus(), refreshVirtualNetwork()]);
  if (model.core?.running) {
    startTrafficPolling();
  }
}

async function restorePrefs(): Promise<void> {
  try {
    const prefs = await api.loadSessionPrefs();
    if (prefs.profileYaml?.trim()) model.profileYaml = prefs.profileYaml;
    if (prefs.selectedAddress?.trim()) model.selectedAddress = prefs.selectedAddress;
    if (prefs.routingMode === "rule" || prefs.routingMode === "global" || prefs.routingMode === "direct") {
      model.routingMode = prefs.routingMode;
    }
    model.systemProxyEnabled = !!prefs.systemProxyEnabled;
    if (prefs.lastSpeedIpRange?.trim()) model.speedIpRange = prefs.lastSpeedIpRange;
    model.speedDisableDownload = prefs.disableDownload !== false;
  } catch {
    // browser preview keeps defaults
  }
}

async function bootstrap(): Promise<void> {
  bindShell();
  paint();
  pushLog(model, "info", "app", "正在准备 ViaSix…");

  try {
    try {
      model.version = await api.appVersion();
    } catch {
      model.version = "dev";
    }
    await restorePrefs();
    await refreshAllStatus();
    model.bootstrapped = true;
    pushLog(model, "success", "app", "初始化完成");
    paint();
    scheduleSavePrefs();
  } catch (error) {
    model.bootstrapError = String(error);
    pushLog(model, "error", "app", `初始化失败：${error}`);
    toast(`初始化失败：${error}`, "error");
    paint();
  }
}

void bootstrap();
