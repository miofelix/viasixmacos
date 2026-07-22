import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

type RoutingMode = "rule" | "global" | "direct";
type CoreStatus = {
  running: boolean;
  pid: number | null;
  message: string;
  controllerPort: number | null;
};
type ControllerHealth = {
  ok: boolean;
  endpoint: string;
  message: string;
  version: string | null;
};
type VirtualNetworkStatus = {
  available: boolean;
  enabled: boolean;
  backend: string;
  message: string;
  wintunPath: string | null;
};
type TrafficSnapshot = {
  live: boolean;
  upBps: number;
  downBps: number;
  uploadTotal: number;
  downloadTotal: number;
  message: string;
};
type SystemProxyStatus = {
  enabled: boolean;
  managedByViasix: boolean;
  endpoint: { host: string; port: number } | null;
  message: string;
};
type ExitIpResult = {
  ip: string;
  family: string;
  source: string;
  message: string;
};
type SpeedTestResult = {
  ip: string;
  sent: string;
  received: string;
  loss: string;
  latency: string;
  speed: string;
  region: string;
};
type SpeedTestResponse = {
  results: SpeedTestResult[];
  message: string;
  resultCsvPath: string;
};
type SessionPrefs = {
  profileYaml: string;
  selectedAddress: string;
  routingMode: string;
  systemProxyEnabled: boolean;
  lastSpeedIpRange: string;
  disableDownload: boolean;
};

const DEFAULT_PROFILE = `proxies:
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

const app = document.querySelector<HTMLDivElement>("#app");
if (!app) {
  throw new Error("#app missing");
}

app.innerHTML = `
  <main class="shell">
    <header>
      <h1>ViaSix <span class="badge" id="app-version">Windows MVP</span></h1>
      <p class="muted">IPv6-first · 投影 · Mihomo · 系统代理 · 出口检测 · CFST 测速</p>
    </header>

    <section class="card">
      <h2>连接配置</h2>
      <label class="field">
        <span>Profile YAML</span>
        <textarea id="profile" rows="10" spellcheck="false" placeholder="粘贴含内联代理的 Mihomo YAML"></textarea>
      </label>
      <div class="row">
        <label class="field grow">
          <span>选中 IPv6</span>
          <input id="selected-ip" type="text" placeholder="2001:db8::1" />
        </label>
        <label class="field">
          <span>模式</span>
          <select id="mode">
            <option value="rule">规则</option>
            <option value="global">全局</option>
            <option value="direct">直连</option>
          </select>
        </label>
      </div>
      <label class="check">
        <input id="sys-proxy" type="checkbox" />
        <span>启用系统代理（127.0.0.1:11451，仅 Windows 生效）</span>
      </label>
      <label class="check">
        <input id="virt-net" type="checkbox" />
        <span id="virt-net-label">虚拟网卡 / Wintun（需 wintun.dll + 通常需管理员）</span>
      </label>
      <div class="actions">
        <button id="btn-project" type="button">生成运行配置</button>
        <button id="btn-start" type="button" class="primary">启动 Mihomo</button>
        <button id="btn-stop" type="button">停止</button>
        <button id="btn-proxy-apply" type="button">应用系统代理</button>
        <button id="btn-proxy-clear" type="button">清除系统代理</button>
        <button id="btn-health" type="button">探测 Controller</button>
        <button id="btn-exit-ip" type="button">检测出口 IP</button>
      </div>
      <p id="status" class="status muted">就绪</p>
      <p id="traffic-status" class="status muted">流量：—</p>
      <p id="proxy-status" class="status muted"></p>
      <p id="health-status" class="status muted"></p>
      <p id="virt-status" class="status muted"></p>
      <p id="exit-ip" class="status muted"></p>
    </section>

    <section class="card">
      <h2>IPv6 测速（CFST）</h2>
      <div class="row">
        <label class="field grow">
          <span>IP / CIDR（可多个，逗号分隔）</span>
          <input id="speed-ip" type="text" placeholder="2606:4700::/32 或单个 IPv6" />
        </label>
        <label class="check speed-dd">
          <input id="speed-dd" type="checkbox" checked />
          <span>仅延迟（-dd，更快）</span>
        </label>
      </div>
      <div class="actions">
        <button id="btn-speed" type="button" class="primary">开始测速</button>
        <button id="btn-apply-best" type="button">应用最佳结果到选中 IPv6</button>
      </div>
      <p id="speed-status" class="status muted">需要先执行 pnpm prebuild 下载 CFST</p>
      <div class="table-wrap">
        <table id="speed-table">
          <thead>
            <tr>
              <th>IP</th>
              <th>延迟</th>
              <th>丢包</th>
              <th>速度</th>
              <th>地区</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>
    </section>

    <section class="card">
      <h2>运行配置预览</h2>
      <pre id="runtime-yaml" class="code"># 点击「生成运行配置」</pre>
    </section>
  </main>
`;

const profileEl = document.querySelector<HTMLTextAreaElement>("#profile")!;
const selectedIpEl = document.querySelector<HTMLInputElement>("#selected-ip")!;
const modeEl = document.querySelector<HTMLSelectElement>("#mode")!;
const sysProxyEl = document.querySelector<HTMLInputElement>("#sys-proxy")!;
const runtimeEl = document.querySelector<HTMLPreElement>("#runtime-yaml")!;
const statusEl = document.querySelector<HTMLParagraphElement>("#status")!;
const proxyStatusEl = document.querySelector<HTMLParagraphElement>("#proxy-status")!;
const trafficStatusEl = document.querySelector<HTMLParagraphElement>("#traffic-status")!;
const healthStatusEl = document.querySelector<HTMLParagraphElement>("#health-status")!;
const virtStatusEl = document.querySelector<HTMLParagraphElement>("#virt-status")!;
const virtNetLabelEl = document.querySelector<HTMLSpanElement>("#virt-net-label")!;
const virtNetEl = document.querySelector<HTMLInputElement>("#virt-net")!;
const exitIpEl = document.querySelector<HTMLParagraphElement>("#exit-ip")!;
const speedIpEl = document.querySelector<HTMLInputElement>("#speed-ip")!;
const speedDdEl = document.querySelector<HTMLInputElement>("#speed-dd")!;
const speedStatusEl = document.querySelector<HTMLParagraphElement>("#speed-status")!;
const speedTableBody = document.querySelector<HTMLTableSectionElement>("#speed-table tbody")!;

let lastSpeedResults: SpeedTestResult[] = [];
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let trafficTimer: ReturnType<typeof setInterval> | null = null;

function setStatus(text: string, isError = false) {
  statusEl.textContent = text;
  statusEl.classList.toggle("error", isError);
}

function currentPrefs(): SessionPrefs {
  return {
    profileYaml: profileEl.value,
    selectedAddress: selectedIpEl.value,
    routingMode: modeEl.value,
    systemProxyEnabled: sysProxyEl.checked,
    lastSpeedIpRange: speedIpEl.value,
    disableDownload: speedDdEl.checked,
  };
}

function scheduleSavePrefs() {
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    void invoke("save_session_prefs", { prefs: currentPrefs() }).catch(() => {
      // ignore when not in tauri webview
    });
  }, 400);
}

async function restorePrefs() {
  try {
    const prefs = await invoke<SessionPrefs>("load_session_prefs");
    if (prefs.profileYaml?.trim()) profileEl.value = prefs.profileYaml;
    if (prefs.selectedAddress?.trim()) selectedIpEl.value = prefs.selectedAddress;
    if (prefs.routingMode) modeEl.value = prefs.routingMode;
    sysProxyEl.checked = !!prefs.systemProxyEnabled;
    if (prefs.lastSpeedIpRange?.trim()) speedIpEl.value = prefs.lastSpeedIpRange;
    speedDdEl.checked = prefs.disableDownload !== false;
  } catch {
    // browser preview: keep defaults
  }
}

function renderSpeedResults(results: SpeedTestResult[]) {
  lastSpeedResults = results;
  speedTableBody.innerHTML = "";
  for (const row of results) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><button type="button" class="linkish" data-ip="${row.ip}">${row.ip}</button></td>
      <td>${row.latency}</td>
      <td>${row.loss}</td>
      <td>${row.speed}</td>
      <td>${row.region}</td>
    `;
    speedTableBody.appendChild(tr);
  }
  speedTableBody.querySelectorAll<HTMLButtonElement>("button[data-ip]").forEach((btn) => {
    btn.addEventListener("click", () => {
      selectedIpEl.value = btn.dataset.ip ?? "";
      setStatus(`已选择节点 ${selectedIpEl.value}`);
    });
  });
}

async function refreshCoreStatus() {
  try {
    const status = await invoke<CoreStatus>("core_status");
    if (status.running) {
      setStatus(`Mihomo 运行中${status.pid != null ? ` (pid ${status.pid})` : ""}`);
    }
  } catch {
    // ignore when not in tauri webview
  }
}

async function refreshProxyStatus() {
  try {
    const status = await invoke<SystemProxyStatus>("system_proxy_status");
    proxyStatusEl.textContent = status.message;
    sysProxyEl.checked = status.enabled && status.managedByViasix;
  } catch (error) {
    proxyStatusEl.textContent = `系统代理状态不可用：${error}`;
  }
}

async function refreshVirtualNetwork() {
  try {
    const status = await invoke<VirtualNetworkStatus>("virtual_network_status");
    virtStatusEl.textContent = status.message;
    virtNetEl.disabled = !status.available;
    virtNetEl.checked = status.enabled;
    virtNetLabelEl.textContent = status.available
      ? "虚拟网卡 / Mihomo TUN + Wintun（启用后需重新启动 Mihomo；通常需管理员）"
      : "虚拟网卡 / Wintun（不可用：请在 Windows 上 pnpm prebuild 拉取 wintun.dll）";
  } catch (error) {
    virtStatusEl.textContent = `虚拟网卡状态不可用：${error}`;
    virtNetEl.disabled = true;
  }
}

virtNetEl.addEventListener("change", async () => {
  try {
    const status = await invoke<VirtualNetworkStatus>("set_virtual_network", {
      enabled: virtNetEl.checked,
    });
    virtStatusEl.textContent = status.message;
    virtStatusEl.classList.remove("error");
    if (status.enabled) {
      setStatus("已请求 TUN：请点击「启动 Mihomo」应用（管理员权限通常必需）");
    }
  } catch (error) {
    virtNetEl.checked = false;
    virtStatusEl.textContent = `虚拟网卡切换失败：${error}`;
    virtStatusEl.classList.add("error");
  }
});

async function refreshTraffic() {
  try {
    const snap = await invoke<TrafficSnapshot>("sample_traffic");
    trafficStatusEl.textContent = snap.live ? `流量：${snap.message}` : `流量：${snap.message}`;
    trafficStatusEl.classList.toggle("error", !snap.live && snap.message.includes("unavailable"));
  } catch {
    trafficStatusEl.textContent = "流量：—";
  }
}

function startTrafficPolling() {
  if (trafficTimer) return;
  void refreshTraffic();
  trafficTimer = setInterval(() => {
    void refreshTraffic();
  }, 1000);
}

function stopTrafficPolling() {
  if (trafficTimer) {
    clearInterval(trafficTimer);
    trafficTimer = null;
  }
  trafficStatusEl.textContent = "流量：—";
}

document.querySelector("#btn-project")!.addEventListener("click", async () => {
  try {
    const mode = modeEl.value as RoutingMode;
    const yaml = await invoke<string>("project_runtime_config", {
      profileYaml: profileEl.value,
      selectedAddress: mode === "direct" ? null : selectedIpEl.value || null,
      routingMode: mode,
    });
    runtimeEl.textContent = yaml;
    setStatus("投影成功");
    scheduleSavePrefs();
  } catch (error) {
    runtimeEl.textContent = String(error);
    setStatus(`投影失败：${error}`, true);
  }
});

document.querySelector("#btn-start")!.addEventListener("click", async () => {
  try {
    const mode = modeEl.value as RoutingMode;
    const status = await invoke<CoreStatus>("start_core", {
      profileYaml: profileEl.value,
      selectedAddress: mode === "direct" ? null : selectedIpEl.value || null,
      routingMode: mode,
      enableSystemProxy: sysProxyEl.checked,
    });
    setStatus(status.message);
    await refreshProxyStatus();
    if (status.running) startTrafficPolling();
  } catch (error) {
    setStatus(`启动失败：${error}`, true);
  }
});

document.querySelector("#btn-stop")!.addEventListener("click", async () => {
  try {
    const status = await invoke<CoreStatus>("stop_core");
    setStatus(status.message);
    await refreshProxyStatus();
    stopTrafficPolling();
  } catch (error) {
    setStatus(`停止失败：${error}`, true);
  }
});

document.querySelector("#btn-proxy-apply")!.addEventListener("click", async () => {
  try {
    const status = await invoke<SystemProxyStatus>("set_system_proxy", {
      enabled: true,
      host: "127.0.0.1",
      port: 11451,
    });
    proxyStatusEl.textContent = status.message;
    sysProxyEl.checked = true;
  } catch (error) {
    proxyStatusEl.textContent = `应用系统代理失败：${error}`;
    proxyStatusEl.classList.add("error");
  }
});

document.querySelector("#btn-proxy-clear")!.addEventListener("click", async () => {
  try {
    const status = await invoke<SystemProxyStatus>("set_system_proxy", {
      enabled: false,
    });
    proxyStatusEl.textContent = status.message;
    proxyStatusEl.classList.remove("error");
    sysProxyEl.checked = false;
  } catch (error) {
    proxyStatusEl.textContent = `清除系统代理失败：${error}`;
    proxyStatusEl.classList.add("error");
  }
});

document.querySelector("#btn-health")!.addEventListener("click", async () => {
  healthStatusEl.textContent = "探测中…";
  healthStatusEl.classList.remove("error");
  try {
    const health = await invoke<ControllerHealth>("probe_controller");
    healthStatusEl.textContent = health.message;
    healthStatusEl.classList.toggle("error", !health.ok);
  } catch (error) {
    healthStatusEl.textContent = `探测失败：${error}`;
    healthStatusEl.classList.add("error");
  }
});

document.querySelector("#btn-exit-ip")!.addEventListener("click", async () => {
  exitIpEl.textContent = "检测中…";
  exitIpEl.classList.remove("error");
  try {
    const result = await invoke<ExitIpResult>("detect_exit_ip");
    exitIpEl.textContent = `${result.message}（来源 ${result.source}）`;
  } catch (error) {
    exitIpEl.textContent = `出口检测失败：${error}`;
    exitIpEl.classList.add("error");
  }
});

document.querySelector("#btn-speed")!.addEventListener("click", async () => {
  speedStatusEl.textContent = "测速进行中，请稍候…";
  speedStatusEl.classList.remove("error");
  try {
    const response = await invoke<SpeedTestResponse>("run_speed_test", {
      request: {
        ipRange: speedIpEl.value.trim() || null,
        disableDownload: speedDdEl.checked,
        httping: true,
        threads: 100,
        pingCount: 4,
        downloadCount: 5,
        downloadTime: 5,
      },
    });
    renderSpeedResults(response.results);
    speedStatusEl.textContent = response.message;
  } catch (error) {
    speedStatusEl.textContent = `测速失败：${error}`;
    speedStatusEl.classList.add("error");
  }
});

document.querySelector("#btn-apply-best")!.addEventListener("click", () => {
  if (lastSpeedResults.length === 0) {
    speedStatusEl.textContent = "没有可应用的测速结果";
    speedStatusEl.classList.add("error");
    return;
  }
  selectedIpEl.value = lastSpeedResults[0].ip;
  speedStatusEl.classList.remove("error");
  speedStatusEl.textContent = `已应用最佳结果：${selectedIpEl.value}`;
  setStatus(`已选择节点 ${selectedIpEl.value}`);
  scheduleSavePrefs();
});

selectedIpEl.value = "2001:db8::1";
speedIpEl.value = "2606:4700::/32";
profileEl.value = DEFAULT_PROFILE;

for (const el of [profileEl, selectedIpEl, modeEl, sysProxyEl, speedIpEl, speedDdEl]) {
  el.addEventListener("change", scheduleSavePrefs);
  el.addEventListener("input", scheduleSavePrefs);
}

void (async () => {
  try {
    const version = await invoke<string>("app_version");
    const badge = document.querySelector("#app-version");
    if (badge) badge.textContent = `v${version}`;
  } catch {
    // ignore
  }
  await restorePrefs();
  await refreshCoreStatus();
  await refreshProxyStatus();
  await refreshVirtualNetwork();
  try {
    const status = await invoke<CoreStatus>("core_status");
    if (status.running) startTrafficPolling();
  } catch {
    // ignore
  }
  scheduleSavePrefs();
})();
