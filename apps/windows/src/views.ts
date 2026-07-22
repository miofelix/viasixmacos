import {
  escapeHtml,
  formatBytes,
  formatRate,
  formatTime,
  isLikelyIPv6,
  sparklinePaths,
  truncateMiddle,
} from "./format";
import { icon } from "./icons";
import {
  canStartProxy,
  configurationReady,
  effectiveProfileSummary,
  filteredLogs,
  hasUsableProfile,
  readinessIssues,
  routingModeLabel,
  selectedNodeSecondary,
  sortedSpeedResults,
  speedResultsFresh,
  type AppModel,
} from "./state";
import {
  ROUTING_MODES,
  SECTIONS,
  type AppSection,
  type NodeSortKey,
  type RoutingMode,
} from "./types";

export function renderShell(): string {
  const nav = SECTIONS.map(
    (s) => `
    <button type="button" class="nav-item" data-section="${s.id}" aria-current="false">
      <span class="nav-icon">${icon(s.icon, 17)}</span>
      <span class="nav-label">${s.title}</span>
    </button>`,
  ).join("");

  return `
  <div class="app-root">
    <aside class="sidebar">
      <div class="brand">
        <div class="brand-mark" aria-hidden="true">V6</div>
        <div class="brand-text">
          <div class="brand-name">ViaSix</div>
          <div class="brand-version" id="brand-version">Windows</div>
        </div>
      </div>
      <nav class="nav" aria-label="主导航">${nav}</nav>
      <div class="sidebar-footer">
        <div class="sidebar-kicker">IPv6 代理入口</div>
        <div class="sidebar-ip" id="sidebar-ip">未选择</div>
        <div class="sidebar-proxy" id="sidebar-proxy"></div>
      </div>
    </aside>
    <div class="divider-v" aria-hidden="true"></div>
    <main class="detail">
      <div id="detail-content" class="detail-content"></div>
      <div id="notice-host" class="notice-host" hidden></div>
      <div id="modal-host" class="modal-host" hidden></div>
    </main>
  </div>`;
}

export function renderSection(model: AppModel): string {
  if (!model.bootstrapped && !model.bootstrapError) {
    return renderBootstrap();
  }
  if (model.bootstrapError) {
    return renderBootstrapFailed(model.bootstrapError);
  }
  switch (model.section) {
    case "overview":
      return renderOverview(model);
    case "nodes":
      return renderNodes(model);
    case "profiles":
      return renderProfiles(model);
    case "logs":
      return renderLogs(model);
    case "settings":
      return renderSettings(model);
  }
}

function renderBootstrap(): string {
  return `
  <div class="center-state">
    <div class="spinner" aria-hidden="true"></div>
    <h1>正在准备 ViaSix…</h1>
    <p class="muted">正在检查会话偏好、运行组件与网络接入能力</p>
  </div>`;
}

function renderBootstrapFailed(message: string): string {
  return `
  <div class="center-state">
    ${icon("warn", 36)}
    <h1>初始化失败</h1>
    <p class="muted">${escapeHtml(message)}</p>
    <button type="button" class="btn btn-primary" data-action="retry-bootstrap">重试</button>
  </div>`;
}

function pageHeader(title: string, subtitle: string, trailing = ""): string {
  return `
  <header class="page-header">
    <div>
      <h1 class="page-title">${title}</h1>
      <p class="page-subtitle">${subtitle}</p>
    </div>
    <div class="page-header-trailing">${trailing}</div>
  </header>`;
}

function statusBadge(
  text: string,
  tone: "neutral" | "accent" | "positive" | "warning" | "negative",
): string {
  return `<span class="badge tone-${tone}">${escapeHtml(text)}</span>`;
}

function stepRow(args: {
  title: string;
  detail: string;
  ready: boolean;
  active: boolean;
  actionLabel?: string;
  actionAttr?: string;
  badgeOnly?: boolean;
}): string {
  const tone = args.active ? "positive" : args.ready ? "accent" : "warning";
  const mark = args.ready || args.active ? icon("check", 14) : icon("warn", 14);
  let trailing = "";
  if (args.actionLabel) {
    trailing = `<button type="button" class="btn btn-ghost btn-sm" data-action="${args.actionAttr ?? ""}">${escapeHtml(args.actionLabel)}</button>`;
  } else {
    trailing = statusBadge(
      args.active ? "已启用" : args.ready ? "已就绪" : "未就绪",
      args.active ? "positive" : args.ready ? "accent" : "warning",
    );
  }
  return `
  <div class="step-row">
    <div class="step-mark tone-${tone}">${mark}</div>
    <div class="step-body">
      <div class="step-title">${escapeHtml(args.title)}</div>
      <div class="step-detail" title="${escapeHtml(args.detail)}">${escapeHtml(args.detail)}</div>
    </div>
    <div class="step-trailing">${trailing}</div>
  </div>`;
}

function renderOverview(model: AppModel): string {
  const running = !!model.core?.running;
  const selectedOk = isLikelyIPv6(model.selectedAddress);
  const issues = readinessIssues(model);
  const virt = model.virtualNetwork;
  const networkReady = virt ? virt.available || !virt.enabled : true;
  const networkActive = running;
  const networkDetail = virt?.enabled
    ? virt.available
      ? "虚拟网卡（Mihomo TUN + Wintun）"
      : "已请求 TUN，但 Wintun 不可用"
    : model.systemProxyEnabled || model.proxy?.enabled
      ? `系统代理 · 本地 mixed 127.0.0.1:${model.mixedPort}`
      : "用户态本地代理（未启用系统代理 / TUN）";

  const headerTone =
    model.core && !running && model.core.message.toLowerCase().includes("fail")
      ? "negative"
      : running
        ? "positive"
        : configurationReady(model)
          ? "accent"
          : "warning";
  const headerText =
    model.routingMode === "direct"
      ? running
        ? "直连已启用"
        : "直连未启用"
      : running
        ? "IPv6 已启用"
        : configurationReady(model)
          ? "就绪"
          : "待配置";

  const routingCards = ROUTING_MODES.map((m) => {
    const selected = model.routingMode === m.id;
    return `
      <button type="button" class="mode-card ${selected ? "is-selected" : ""}" data-routing="${m.id}" ${running ? "disabled" : ""}>
        <span class="mode-title">${m.title}</span>
      </button>`;
  }).join("");

  const modeDesc =
    ROUTING_MODES.find((m) => m.id === model.routingMode)?.description ?? "";

  const traffic = model.traffic;
  const up = traffic?.live ? formatRate(traffic.upBps) : "—";
  const down = traffic?.live ? formatRate(traffic.downBps) : "—";
  const upTotal = traffic ? formatBytes(traffic.uploadTotal) : "—";
  const downTotal = traffic ? formatBytes(traffic.downloadTotal) : "—";
  const trafficStatus = !running
    ? "未连接"
    : traffic?.live
      ? "实时"
      : "连接中";

  const spark = sparklinePaths(model.trafficHistory, 560, 96);
  const sparkSvg =
    model.trafficHistory.length > 1
      ? `<svg class="sparkline" viewBox="0 0 560 96" preserveAspectRatio="none" aria-label="流量曲线">
           <path class="spark-area" d="${spark.areaDown}"></path>
           <path class="spark-down" d="${spark.down}"></path>
           <path class="spark-up" d="${spark.up}"></path>
         </svg>`
      : `<div class="sparkline-empty">${running ? "等待流量数据…" : "暂无流量数据"}</div>`;

  const entryPrimary = selectedOk
    ? model.selectedAddress
    : model.selectedAddress.trim()
      ? model.selectedAddress
      : "尚未选择";
  const exitPrimary = model.exitIp?.ip || (model.busy.exitIp ? "检测中…" : "尚未检测");
  const exitSecondary = model.exitIp
    ? `${model.exitIp.family.toUpperCase()} · ${model.exitIp.source}`
    : model.busy.exitIp
      ? "正在查询公网出口"
      : "出口可能是 IPv4，不代表入口地址族";

  const startDisabled = !canStartProxy(model) || model.busy.start;
  const actionBtn = running
    ? `<button type="button" class="btn btn-danger" data-action="stop-core" ${model.busy.stop ? "disabled" : ""}>
         ${icon("stop", 16)} <span>${model.busy.stop ? "停止中…" : "停止连接"}</span>
       </button>`
    : `<button type="button" class="btn btn-primary" data-action="start-core" ${startDisabled ? "disabled" : ""} title="${escapeHtml(issues[0]?.message ?? "启动连接")}">
         ${icon("play", 16)} <span>${model.busy.start ? "启动中…" : "启动连接"}</span>
       </button>`;

  const readinessBlock =
    issues.length > 0 && !running
      ? `<div class="callout tone-warning">
           <div class="callout-title">${icon("warn", 14)} 启动前需处理</div>
           <ul class="issue-list">
             ${issues
               .map(
                 (i) =>
                   `<li>
                      <span>${escapeHtml(i.message)}</span>
                      ${
                        i.action
                          ? `<button type="button" class="btn btn-ghost btn-sm" data-action="${
                              i.action === "openSettings"
                                ? "goto-settings"
                                : i.action === "gotoNodes"
                                  ? "goto-nodes"
                                  : "goto-profiles"
                            }">处理</button>`
                          : ""
                      }
                    </li>`,
               )
               .join("")}
           </ul>
         </div>`
      : "";

  return `
  ${pageHeader("首页", "IPv6 代理链路状态与控制", statusBadge(headerText, headerTone))}
  <div class="page-scroll">
    ${readinessBlock}
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("network", 16)} <span>IPv6 链路</span></div>
        ${actionBtn}
      </div>
      <div class="card-body stack-0">
        ${stepRow({
          title: "网络接入",
          detail: networkDetail,
          ready: networkReady,
          active: networkActive,
          actionLabel: virt && !virt.available ? "打开设置" : undefined,
          actionAttr: "goto-settings",
        })}
        <div class="row-divider"></div>
        ${stepRow({
          title: "IPv6 节点",
          detail: selectedOk ? model.selectedAddress : "尚未选择有效 IPv6 地址",
          ready: selectedOk || model.routingMode === "direct",
          active: selectedOk && running,
          actionLabel: selectedOk ? "更换" : "选择",
          actionAttr: "goto-nodes",
        })}
        <div class="row-divider"></div>
        ${stepRow({
          title: "连接配置",
          detail:
            model.routingMode === "direct"
              ? "直连模式不加载远程代理配置"
              : hasUsableProfile(model)
                ? "主内联节点可注入当前 IPv6 地址"
                : effectiveProfileSummary(model).hasInlineProxy
                  ? "配置需要替换示例入口"
                  : "配置需要包含可注入地址的内联代理",
          ready:
            model.routingMode === "direct" ||
            (effectiveProfileSummary(model).hasInlineProxy &&
              !effectiveProfileSummary(model).looksLikeExample),
          active:
            running &&
            (model.routingMode === "direct" || hasUsableProfile(model)),
          actionLabel: "管理",
          actionAttr: "goto-profiles",
        })}
        <div class="row-divider"></div>
        ${stepRow({
          title: "公网流量",
          detail: running
            ? traffic?.message || "代理运行中"
            : configurationReady(model)
              ? "配置就绪，可启动"
              : "完成节点与配置后可启动",
          ready: configurationReady(model),
          active: running,
        })}
      </div>
    </section>

    <div class="grid-2">
      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("globe", 16)} <span>代理模式</span></div>
        </div>
        <div class="card-body">
          <div class="mode-row">${routingCards}</div>
          <p class="help-text">${escapeHtml(modeDesc)}</p>
          <p class="help-text muted">routingMode 与网络接入相互独立；运行中切换模式需先停止连接。</p>
        </div>
      </section>

      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("network", 16)} <span>网络设置</span></div>
        </div>
        <div class="card-body stack-0">
          <label class="setting-row">
            <div>
              <div class="setting-title">系统代理</div>
              <div class="setting-detail">独立开关 · Windows HTTP/HTTPS → 127.0.0.1:11451</div>
            </div>
            <input type="checkbox" id="toggle-sys-proxy" ${model.systemProxyEnabled || model.proxy?.enabled ? "checked" : ""} ${model.busy.sysProxy ? "disabled" : ""} />
          </label>
          <div class="row-divider"></div>
          <label class="setting-row">
            <div>
              <div class="setting-title">虚拟网卡模式</div>
              <div class="setting-detail">${escapeHtml(virt?.message || "Mihomo TUN + Wintun（切换后需重启内核）")}</div>
            </div>
            <input type="checkbox" id="toggle-virt-net" ${model.virtualNetworkEnabled ? "checked" : ""} ${virt && !virt.available ? "disabled" : ""} />
          </label>
        </div>
      </section>
    </div>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("info", 16)} <span>流量统计</span></div>
        ${statusBadge(trafficStatus, running ? (traffic?.live ? "positive" : "accent") : "neutral")}
      </div>
      <div class="card-body">
        <div class="sparkline-wrap" id="sparkline-host">${sparkSvg}</div>
        <div class="metric-grid" id="metric-grid">
          <div class="metric tone-accent"><div class="metric-label">${icon("arrow-up", 14)} 上传</div><div class="metric-value" data-metric="up">${up}</div></div>
          <div class="metric tone-positive"><div class="metric-label">${icon("arrow-down", 14)} 下载</div><div class="metric-value" data-metric="down">${down}</div></div>
          <div class="metric"><div class="metric-label">内存</div><div class="metric-value" data-metric="mem">${traffic?.memoryInUse ? formatBytes(traffic.memoryInUse) : "—"}</div></div>
          <div class="metric tone-accent"><div class="metric-label">总上传</div><div class="metric-value" data-metric="up-total">${upTotal}</div></div>
          <div class="metric tone-positive"><div class="metric-label">总下载</div><div class="metric-value" data-metric="down-total">${downTotal}</div></div>
          <div class="metric"><div class="metric-label">状态</div><div class="metric-value" data-metric="status">${running ? (traffic?.live ? "实时采集" : "连接中") : "未连接"}</div></div>
        </div>
        <p class="help-text muted" id="traffic-help">${escapeHtml(traffic?.message || (running ? "速率 /connections · 内存 /memory；启动后持续刷新曲线" : "启动连接后显示实时上下行速率、累计流量、内存与曲线"))}</p>
      </div>
    </section>

    <div class="grid-2">
      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("nodes", 16)} <span>IP 信息</span></div>
          <div class="inline-actions">
            <button type="button" class="btn btn-ghost btn-sm" data-action="goto-nodes">选择节点</button>
            <button type="button" class="btn btn-ghost btn-sm" data-action="test-current-node" ${model.busy.nodeTest || !selectedOk ? "disabled" : ""}>
              ${model.busy.nodeTest ? "测节点…" : "测当前节点"}
            </button>
            <button type="button" class="btn btn-ghost btn-sm" data-action="detect-exit" ${model.busy.exitIp ? "disabled" : ""}>
              ${model.busy.exitIp ? "检测中…" : "检测出口"}
            </button>
          </div>
        </div>
        <div class="card-body stack-12">
          <div class="ip-block">
            <div class="ip-label-row">
              <span class="ip-label">IPv6 入口</span>
              ${selectedOk ? statusBadge("IPv6", "accent") : statusBadge("未就绪", "warning")}
            </div>
            <div class="ip-primary-row">
              <div class="ip-primary mono" title="${escapeHtml(entryPrimary)}">${escapeHtml(truncateMiddle(entryPrimary, 48))}</div>
              <button type="button" class="icon-btn" data-action="copy-text" data-copy="${escapeHtml(selectedOk ? model.selectedAddress : "")}" ${selectedOk ? "" : "disabled"} title="复制">${icon("copy", 14)}</button>
            </div>
            <div class="ip-secondary">${escapeHtml(selectedNodeSecondary(model))}</div>
            <p class="help-text muted">${escapeHtml(model.nodeTestMessage)}</p>
          </div>
          <div class="row-divider flush"></div>
          <div class="ip-block">
            <div class="ip-label-row">
              <span class="ip-label">公网出口</span>
              ${
                model.exitIp
                  ? statusBadge(model.exitIp.family.toUpperCase(), "neutral")
                  : statusBadge("—", "neutral")
              }
            </div>
            <div class="ip-primary-row">
              <div class="ip-primary mono" title="${escapeHtml(exitPrimary)}">${escapeHtml(truncateMiddle(exitPrimary, 48))}</div>
              <button type="button" class="icon-btn" data-action="copy-text" data-copy="${escapeHtml(model.exitIp?.ip ?? "")}" ${model.exitIp?.ip ? "" : "disabled"} title="复制">${icon("copy", 14)}</button>
            </div>
            <div class="ip-secondary">${escapeHtml(exitSecondary)}</div>
            <div class="segmented" role="group" aria-label="出口地址族">
              ${(["auto", "ipv4", "ipv6"] as const)
                .map(
                  (m) =>
                    `<button type="button" class="seg-btn ${model.exitIpMode === m ? "is-selected" : ""}" data-exit-mode="${m}">${m === "auto" ? "自动" : m.toUpperCase()}</button>`,
                )
                .join("")}
            </div>
          </div>
        </div>
      </section>

      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("shield", 16)} <span>应用信息</span></div>
        </div>
        <div class="card-body stack-0">
          ${infoRow("版本", `v${model.version}`)}
          <div class="row-divider"></div>
          ${infoRow("系统", "Windows · Tauri 2 / WebView2")}
          <div class="row-divider"></div>
          ${infoRow(
            "运行",
            running
              ? `Mihomo${model.core?.pid != null ? ` · pid ${model.core.pid}` : ""}`
              : "已停止",
          )}
          <div class="row-divider"></div>
          ${infoRow("代理", `127.0.0.1:${model.mixedPort}`)}
          <div class="row-divider"></div>
          ${infoRow("控制", model.core?.controllerPort != null ? `127.0.0.1:${model.core.controllerPort}` : `127.0.0.1:${model.controllerPort}`)}
          <div class="row-divider"></div>
          ${infoRow("模式", routingModeLabel(model.routingMode))}
          <div class="app-links">
            <a class="btn btn-sm" href="https://github.com/miofelix/ViaSix" target="_blank" rel="noreferrer">仓库</a>
            <button type="button" class="btn btn-sm" data-action="goto-settings">设置</button>
            <button type="button" class="btn btn-sm" data-action="goto-logs">日志</button>
          </div>
          <div class="inline-actions" style="margin-top:10px">
            <button type="button" class="btn btn-sm" data-action="probe-connectivity" ${!running || model.busy.connectivity ? "disabled" : ""}>
              ${model.busy.connectivity ? "探测中…" : "代理连通性"}
            </button>
          </div>
          <p class="help-text muted">${escapeHtml(model.connectivityMessage)}</p>
        </div>
      </section>
    </div>
  </div>`;
}

function infoRow(label: string, value: string): string {
  return `
  <div class="info-row">
    <span class="info-label">${escapeHtml(label)}</span>
    <span class="info-value mono">${escapeHtml(value)}</span>
  </div>`;
}

function sortHeader(label: string, key: NodeSortKey, model: AppModel): string {
  const active = model.nodeSortKey === key;
  const arrow = active ? (model.nodeSortAsc ? " ↑" : " ↓") : "";
  return `<th><button type="button" class="th-sort ${active ? "is-active" : ""}" data-sort="${key}">${escapeHtml(label)}${arrow}</button></th>`;
}

function renderNodes(model: AppModel): string {
  const results = sortedSpeedResults(model);
  const fresh = speedResultsFresh(model);
  const rows =
    results.length === 0
      ? `<tr><td colspan="8" class="empty-cell">暂无测速结果。填写 IP/CIDR 并开始测速后，可在此排序、复制与应用节点。</td></tr>`
      : results
          .map((row, index) => {
            const selected = row.ip === model.selectedAddress;
            const highlighted = row.ip === model.selectedResultIp;
            return `
            <tr class="${selected ? "is-selected" : ""} ${highlighted ? "is-focused" : ""}" data-row-ip="${escapeHtml(row.ip)}">
              <td class="td-actions">
                <input type="radio" name="node-pick" data-focus-ip="${escapeHtml(row.ip)}" ${highlighted || selected ? "checked" : ""} aria-label="选择 ${escapeHtml(row.ip)}" />
              </td>
              <td>
                <button type="button" class="linkish" data-select-ip="${escapeHtml(row.ip)}">
                  ${escapeHtml(row.ip)}
                </button>
                ${index === 0 && model.nodeSortKey === "latency" && model.nodeSortAsc ? `<span class="chip">推荐</span>` : ""}
                ${selected ? `<span class="chip chip-accent">当前</span>` : ""}
              </td>
              <td class="mono">${escapeHtml(row.sent)}</td>
              <td class="mono">${escapeHtml(row.received)}</td>
              <td class="mono">${escapeHtml(row.loss)}</td>
              <td class="mono">${escapeHtml(row.latency)}</td>
              <td class="mono">${escapeHtml(row.speed)}</td>
              <td>${escapeHtml(row.region)}</td>
            </tr>`;
          })
          .join("");

  const paramsOpen = model.showSpeedParams;
  const p = model.speedParams;

  return `
  ${pageHeader(
    "IPv6 优选",
    "测速并选择 IPv6 地址",
    model.selectedAddress
      ? statusBadge(
          truncateMiddle(model.selectedAddress, 28),
          isLikelyIPv6(model.selectedAddress) ? "accent" : "warning",
        )
      : statusBadge("未选择", "warning"),
  )}
  <div class="page-scroll">
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("nodes", 16)} <span>测速状态</span></div>
        ${
          model.busy.speed
            ? statusBadge("测速中", "accent")
            : results.length > 0
              ? statusBadge(fresh ? "结果可用" : "结果可能过期", fresh ? "positive" : "warning")
              : statusBadge("空闲", "neutral")
        }
      </div>
      <div class="card-body">
        ${
          model.busy.speed
            ? `<div class="progress-bar"><div class="progress-indeterminate"></div></div>
               <p class="help-text">正在运行 CFST，请勿关闭窗口…</p>`
            : `<p class="help-text">${escapeHtml(model.speedMessage)}</p>`
        }
        <div class="form-row">
          <label class="field grow">
            <span>IP / CIDR（可多个，逗号分隔）</span>
            <input id="speed-ip" type="text" value="${escapeHtml(model.speedIpRange)}" placeholder="2606:4700::/32 或单个 IPv6" />
          </label>
          <label class="check field-align">
            <input id="speed-dd" type="checkbox" ${model.speedDisableDownload ? "checked" : ""} />
            <span>仅延迟（-dd）</span>
          </label>
        </div>
        ${
          model.ipPresets.length
            ? `<div class="preset-row">
                 ${model.ipPresets
                   .map(
                     (p) =>
                       `<button type="button" class="btn btn-sm" data-action="apply-preset" data-preset="${escapeHtml(p.id)}" title="${escapeHtml(p.description)}">${escapeHtml(p.title)}</button>`,
                   )
                   .join("")}
               </div>`
            : ""
        }
        <div class="inline-actions wrap">
          <button type="button" class="btn btn-primary" data-action="run-speed" ${model.busy.speed ? "disabled" : ""}>
            ${model.busy.speed ? "测速中…" : "开始测速"}
          </button>
          <button type="button" class="btn btn-danger" data-action="stop-speed" ${model.busy.speed ? "" : "disabled"}>
            停止测速
          </button>
          <button type="button" class="btn" data-action="apply-best" ${results.length === 0 ? "disabled" : ""}>
            应用最佳结果
          </button>
          <button type="button" class="btn" data-action="apply-selected" ${model.selectedResultIp || model.selectedAddress ? "" : "disabled"}>
            应用所选节点
          </button>
          <button type="button" class="btn btn-ghost" data-action="toggle-speed-params">
            ${icon("params", 14)} ${paramsOpen ? "收起参数" : "高级参数"}
          </button>
        </div>
        ${
          paramsOpen
            ? `<div class="params-grid">
                <label class="field"><span>线程 (-n)</span><input id="sp-threads" type="number" min="1" max="1000" value="${p.threads}" /></label>
                <label class="field"><span>Ping 次数 (-t)</span><input id="sp-ping" type="number" min="1" max="50" value="${p.pingCount}" /></label>
                <label class="field"><span>下载数 (-dn)</span><input id="sp-dn" type="number" min="1" max="50" value="${p.downloadCount}" /></label>
                <label class="field"><span>下载时长 (-dt 秒)</span><input id="sp-dt" type="number" min="1" max="60" value="${p.downloadTime}" /></label>
                <label class="field"><span>端口 (-tp)</span><input id="sp-port" type="number" min="1" max="65535" value="${p.port}" /></label>
                <label class="check field-align"><input id="sp-httping" type="checkbox" ${p.httping ? "checked" : ""} /><span>HTTPing</span></label>
              </div>
              <p class="help-text muted">参数会写入会话偏好；与 macOS 测速参数面板对应，完整保留 CFST 控制项。</p>`
            : ""
        }
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("logs", 16)} <span>候选节点</span></div>
        <div class="inline-actions">
          <span class="muted small">${results.length} 条</span>
          <button type="button" class="btn btn-ghost btn-sm" data-action="copy-selected-node" ${model.selectedResultIp || model.selectedAddress ? "" : "disabled"} title="复制所选 IP">
            ${icon("copy", 14)} 复制
          </button>
        </div>
      </div>
      <div class="card-body pad-0">
        <div class="table-wrap table-tall">
          <table class="data-table">
            <thead>
              <tr>
                <th></th>
                ${sortHeader("IP", "ip", model)}
                ${sortHeader("已发", "sent", model)}
                ${sortHeader("已收", "received", model)}
                ${sortHeader("丢包", "loss", model)}
                ${sortHeader("延迟", "latency", model)}
                ${sortHeader("速度", "speed", model)}
                ${sortHeader("地区", "region", model)}
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      </div>
    </section>

    <section class="card soft">
      <div class="card-body">
        <p class="help-text">单击 IP 可直接应用；若代理正在运行，将提示是否重新连接。当前入口：
          <span class="mono">${escapeHtml(model.selectedAddress || "—")}</span>
        </p>
        <p class="help-text muted">测速只负责候选排序；启动时由投影将选中 IPv6 写入主代理 server。结果默认按延迟升序，「推荐」标记对应当前排序下的第一条。</p>
      </div>
    </section>
  </div>`;
}

function renderProfiles(model: AppModel): string {
  const summary = effectiveProfileSummary(model);
  const tone =
    model.routingMode === "direct"
      ? "positive"
      : hasUsableProfile(model)
        ? "positive"
        : summary.hasInlineProxy
          ? "warning"
          : "warning";
  const status =
    model.routingMode === "direct"
      ? "直连"
      : hasUsableProfile(model)
        ? "已配置"
        : summary.looksLikeExample
          ? "示例/待替换"
          : summary.hasInlineProxy
            ? "可投影"
            : "未配置";

  return `
  ${pageHeader(
    "连接配置",
    "管理用于承载当前 IPv6 地址的代理入口",
    `<div class="inline-actions">
       <button type="button" class="btn btn-sm" data-action="import-profile">${icon("export", 14)} 导入</button>
       ${statusBadge(status, tone)}
     </div>`,
  )}
  <div class="page-scroll">
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("profile", 16)} <span>当前代理入口</span></div>
        ${statusBadge(
          summary.primaryType ? summary.primaryType.toUpperCase() : "YAML",
          "accent",
        )}
      </div>
      <div class="card-body">
        <div class="profile-summary">
          <div class="profile-icon">${icon("profile", 22)}</div>
          <div>
            <div class="profile-name">${escapeHtml(summary.primaryName ?? "ViaSix 代理入口")}</div>
            <div class="profile-meta muted">
              ${summary.proxyCount} 个内联代理
              ${summary.hasXviasix ? " · 含 x-viasix" : " · 无 x-viasix"}
              ${summary.looksLikeExample ? " · 示例配置" : ""}
            </div>
          </div>
        </div>
        ${
          summary.notes.length
            ? `<ul class="note-list">${summary.notes.map((n) => `<li>${escapeHtml(n)}</li>`).join("")}</ul>`
            : ""
        }
        <label class="field">
          <span>Profile YAML（内联主代理 · x-viasix）</span>
          <textarea id="profile-yaml" rows="14" spellcheck="false">${escapeHtml(model.profileYaml)}</textarea>
        </label>
        <div class="form-row">
          <label class="field grow">
            <span>选中 IPv6（运行时注入）</span>
            <input id="profile-selected-ip" type="text" value="${escapeHtml(model.selectedAddress)}" placeholder="2001:db8::1" />
          </label>
          <label class="field">
            <span>模式</span>
            <select id="profile-mode">
              ${(["rule", "global", "direct"] as RoutingMode[])
                .map(
                  (m) =>
                    `<option value="${m}" ${model.routingMode === m ? "selected" : ""}>${routingModeLabel(m)}</option>`,
                )
                .join("")}
            </select>
          </label>
        </div>
        <div class="inline-actions wrap">
          <button type="button" class="btn" data-action="import-profile">${icon("export", 14)} 导入文件</button>
          <button type="button" class="btn btn-primary" data-action="project-config" ${model.busy.project ? "disabled" : ""}>
            ${model.busy.project ? "生成中…" : "生成运行配置"}
          </button>
          <button type="button" class="btn" data-action="start-core" ${!canStartProxy(model) || model.busy.start ? "disabled" : ""}>
            启动 Mihomo
          </button>
          <button type="button" class="btn" data-action="stop-core" ${model.busy.stop || !model.core?.running ? "disabled" : ""}>
            停止
          </button>
          <button type="button" class="btn btn-ghost" data-action="copy-profile-yaml">
            ${icon("copy", 14)} 复制 YAML
          </button>
        </div>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("logs", 16)} <span>运行配置预览</span></div>
        <button type="button" class="btn btn-ghost btn-sm" data-action="copy-runtime-yaml">
          ${icon("copy", 14)} 复制
        </button>
      </div>
      <div class="card-body pad-0">
        <pre class="code-block" id="runtime-yaml">${escapeHtml(model.runtimeYaml)}</pre>
      </div>
    </section>

    <section class="card soft">
      <div class="card-body stack-8">
        <div class="card-title inline">${icon("shield", 16)} <span>安全说明</span></div>
        <p class="help-text">导入 YAML 中的 Controller、TUN、监听等字段不会进入运行配置；仅投影后的单 IPv6 主代理（或直连规则）会交给 Mihomo。</p>
        <p class="help-text muted">与 macOS / contracts 对齐：Provider-only 与 IPv4 选择会被拒绝。直连模式不要求节点或 profile。</p>
      </div>
    </section>
  </div>`;
}

function renderLogs(model: AppModel): string {
  const visible = filteredLogs(model);
  const rows =
    visible.length === 0
      ? `<div class="empty-state">
           ${icon("logs", 28)}
           <h3>暂无运行记录</h3>
           <p>开始节点测速或启动本地代理后，记录会显示在这里。</p>
         </div>`
      : visible
          .map(
            (e) => `
          <div class="log-row level-${e.level}">
            <span class="log-time mono">${formatTime(e.at)}</span>
            <span class="log-source">${e.source}</span>
            <span class="log-level">${e.level}</span>
            <span class="log-msg">${escapeHtml(e.message)}</span>
          </div>`,
          )
          .join("");

  return `
  ${pageHeader(
    "日志",
    "实时查看本地代理与节点测速记录",
    `<div class="inline-actions">
       <button type="button" class="btn btn-ghost btn-sm" data-action="toggle-log-order" title="切换排序">
         ${icon("sort", 14)} ${model.logNewestFirst ? "最新在上" : "最新在下"}
       </button>
       <button type="button" class="btn btn-ghost btn-sm" data-action="export-logs" ${model.logs.length === 0 ? "disabled" : ""}>
         ${icon("export", 14)} 导出
       </button>
       <button type="button" class="btn btn-ghost btn-sm" data-action="clear-logs" ${model.logs.length === 0 ? "disabled" : ""}>
         ${icon("trash", 14)} 清空
       </button>
     </div>`,
  )}
  <div class="page-scroll">
    <section class="card">
      <div class="card-body">
        <div class="form-row filters">
          <label class="field grow">
            <span>搜索</span>
            <input id="log-query" type="search" value="${escapeHtml(model.logFilter.query)}" placeholder="过滤消息…" />
          </label>
          <label class="field">
            <span>来源</span>
            <select id="log-source">
              ${["all", "app", "core", "proxy", "speed", "network", "config"]
                .map(
                  (s) =>
                    `<option value="${s}" ${model.logFilter.source === s ? "selected" : ""}>${s === "all" ? "全部" : s}</option>`,
                )
                .join("")}
            </select>
          </label>
          <label class="field">
            <span>级别</span>
            <select id="log-level">
              ${["all", "info", "success", "warn", "error"]
                .map(
                  (l) =>
                    `<option value="${l}" ${model.logFilter.level === l ? "selected" : ""}>${l === "all" ? "全部" : l}</option>`,
                )
                .join("")}
            </select>
          </label>
        </div>
        <p class="help-text muted">${visible.length} / ${model.logs.length} 条 · 客户端会话日志（最多保留约 800 条）</p>
      </div>
    </section>
    <section class="card">
      <div class="card-body pad-0 log-list" id="log-list">${rows}</div>
    </section>
  </div>`;
}

function renderSettings(model: AppModel): string {
  const virt = model.virtualNetwork;
  const virtTone = !virt
    ? "neutral"
    : virt.enabled && virt.available
      ? "positive"
      : virt.available
        ? "accent"
        : "warning";
  const issues = readinessIssues(model);

  return `
  ${pageHeader("设置", "连接、网络接入与运行组件")}
  <div class="page-scroll">
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("settings", 16)} <span>本机代理</span></div>
      </div>
      <div class="card-body">
        <div class="form-row">
          <label class="field">
            <span>Mixed 端口</span>
            <input id="settings-mixed-port" type="number" min="1" max="65535" value="${model.mixedPort}" ${model.core?.running ? "disabled" : ""} />
          </label>
          <label class="field">
            <span>Controller 端口</span>
            <input id="settings-controller-port" type="number" min="1" max="65535" value="${model.controllerPort}" ${model.core?.running ? "disabled" : ""} />
          </label>
        </div>
        <p class="help-text muted">对齐 macOS local-proxy 端口语义；运行中不可修改。默认 11451 / 9090。</p>
        <label class="check" style="margin-top:10px">
          <input type="checkbox" id="settings-close-tray" ${model.closeToTray ? "checked" : ""} />
          <span>关闭窗口时隐藏到系统托盘（托盘可显示 / 停止 / 退出）</span>
        </label>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("settings", 16)} <span>运行时</span></div>
        ${statusBadge(model.core?.running ? "运行中" : "已停止", model.core?.running ? "positive" : "neutral")}
      </div>
      <div class="card-body stack-0">
        <div class="setting-row static">
          <div>
            <div class="setting-title">Mihomo 内核</div>
            <div class="setting-detail">${escapeHtml(model.core?.message || "状态未知 — 启动后显示 pid / 端口")}</div>
          </div>
          <div class="inline-actions">
            <button type="button" class="btn btn-sm" data-action="refresh-status">${icon("refresh", 14)} 刷新</button>
          </div>
        </div>
        <div class="row-divider"></div>
        <div class="setting-row static">
          <div>
            <div class="setting-title">Controller 健康</div>
            <div class="setting-detail">${escapeHtml(model.controller?.message || "尚未探测")}${model.controller?.version ? ` · v${escapeHtml(model.controller.version)}` : ""}</div>
          </div>
          <button type="button" class="btn btn-sm" data-action="probe-controller" ${model.busy.health ? "disabled" : ""}>
            ${model.busy.health ? "探测中…" : "探测"}
          </button>
        </div>
        <div class="row-divider"></div>
        <div class="setting-row static">
          <div>
            <div class="setting-title">系统代理</div>
            <div class="setting-detail">${escapeHtml(model.proxy?.message || "—")}</div>
          </div>
          <div class="inline-actions">
            <button type="button" class="btn btn-sm" data-action="apply-sys-proxy" ${model.busy.sysProxy ? "disabled" : ""}>应用</button>
            <button type="button" class="btn btn-sm" data-action="clear-sys-proxy" ${model.busy.sysProxy ? "disabled" : ""}>清除</button>
          </div>
        </div>
        <div class="row-divider"></div>
        <div class="setting-row static">
          <div>
            <div class="setting-title">配置就绪</div>
            <div class="setting-detail">${issues.length === 0 ? "可以启动连接" : issues.map((i) => i.message).join("；")}</div>
          </div>
          ${statusBadge(issues.length === 0 ? "就绪" : `${issues.length} 项`, issues.length === 0 ? "positive" : "warning")}
        </div>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("network", 16)} <span>虚拟网卡服务</span></div>
        ${statusBadge(virt?.enabled ? "已请求" : virt?.available ? "可用" : "不可用", virtTone)}
      </div>
      <div class="card-body stack-8">
        <div class="kv"><span>后端</span><span>${escapeHtml(virt?.backend || "—")}</span></div>
        <div class="kv"><span>Wintun</span><span class="mono small">${escapeHtml(virt?.wintunPath || "未找到")}</span></div>
        <p class="help-text">${escapeHtml(virt?.message || "")}</p>
        <p class="help-text muted">Windows 使用进程内 Mihomo TUN + Wintun.dll（通常需管理员）。与 macOS 特权 LaunchDaemon 路径不同，但产品开关语义一致：可与系统代理同时启用；切换后需重新启动 Mihomo。</p>
        <label class="check">
          <input type="checkbox" id="settings-virt-net" ${model.virtualNetworkEnabled ? "checked" : ""} ${virt && !virt.available ? "disabled" : ""} />
          <span>启用虚拟网卡（下次启动 Mihomo 时生效）</span>
        </label>
        <div class="form-row" style="margin-top:12px">
          <label class="field">
            <span>TUN stack</span>
            <select id="settings-tun-stack" ${model.core?.running ? "disabled" : ""}>
              ${["mixed", "system", "gvisor"]
                .map(
                  (s) =>
                    `<option value="${s}" ${model.tunStack === s ? "selected" : ""}>${s}</option>`,
                )
                .join("")}
            </select>
          </label>
          <label class="field">
            <span>TUN MTU</span>
            <input id="settings-tun-mtu" type="number" min="1280" max="9000" value="${model.tunMtu}" ${model.core?.running ? "disabled" : ""} />
          </label>
        </div>
        <p class="help-text muted">对齐 macOS local-proxy 的 tunStack / tunMTU；进程内 Mihomo TUN + Wintun，通常需管理员。</p>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("logs", 16)} <span>内核日志</span></div>
        <button type="button" class="btn btn-ghost btn-sm" data-action="refresh-core-log">${icon("refresh", 14)} 刷新</button>
      </div>
      <div class="card-body pad-0">
        <pre class="code-block core-log">${escapeHtml(model.coreLog || "（尚无 mihomo 日志 — 启动内核后写入 runtime/mihomo.log）")}</pre>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("globe", 16)} <span>出口检测</span></div>
      </div>
      <div class="card-body">
        <p class="help-text muted">与首页地址族选择同步；可指定 IPv4 / IPv6 探测端点。</p>
        <div class="segmented" role="group" aria-label="出口地址族">
          ${(["auto", "ipv4", "ipv6"] as const)
            .map(
              (m) =>
                `<button type="button" class="seg-btn ${model.exitIpMode === m ? "is-selected" : ""}" data-exit-mode="${m}">${m === "auto" ? "自动" : m.toUpperCase()}</button>`,
            )
            .join("")}
        </div>
        <div class="inline-actions" style="margin-top:12px">
          <button type="button" class="btn" data-action="detect-exit" ${model.busy.exitIp ? "disabled" : ""}>
            ${model.busy.exitIp ? "检测中…" : "立即检测"}
          </button>
        </div>
        <p class="help-text">${model.exitIp ? escapeHtml(`${model.exitIp.message}（${model.exitIp.source}）`) : "尚未检测"}</p>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("info", 16)} <span>关于</span></div>
      </div>
      <div class="card-body stack-8">
        <div class="kv"><span>应用</span><span>ViaSix for Windows</span></div>
        <div class="kv"><span>版本</span><span>v${escapeHtml(model.version)}</span></div>
        <div class="kv"><span>本地 mixed</span><span>127.0.0.1:${model.mixedPort}</span></div>
        <div class="kv"><span>Controller</span><span>127.0.0.1:${model.controllerPort}</span></div>
        <div class="kv"><span>数据目录</span><span class="mono small" title="${escapeHtml(model.dataDir)}">${escapeHtml(truncateMiddle(model.dataDir || "—", 36))}</span></div>
        <div class="kv"><span>投影契约</span><span>contracts/fixtures/mihomo-config</span></div>
        <div class="inline-actions" style="margin-top:8px">
          <button type="button" class="btn btn-sm" data-action="open-data-dir">打开数据目录</button>
        </div>
        <p class="help-text muted">快捷键：<span class="mono">1–5</span> 切换分区（输入框外），<span class="mono">Ctrl/⌘+Enter</span> 启动/停止连接。关闭窗口默认进托盘。</p>
      </div>
    </section>
  </div>`;
}

export function syncChrome(model: AppModel): void {
  document.querySelectorAll<HTMLButtonElement>(".nav-item").forEach((btn) => {
    const id = btn.dataset.section as AppSection;
    const selected = id === model.section;
    btn.classList.toggle("is-selected", selected);
    btn.setAttribute("aria-current", selected ? "page" : "false");
  });

  const brand = document.querySelector("#brand-version");
  if (brand) brand.textContent = model.version !== "—" ? `v${model.version}` : "Windows";

  const sidebarIp = document.querySelector<HTMLElement>("#sidebar-ip");
  if (sidebarIp) {
    sidebarIp.textContent = model.selectedAddress.trim()
      ? model.selectedAddress
      : "未选择";
    sidebarIp.title = model.selectedAddress;
  }

  const dock = document.querySelector<HTMLElement>("#sidebar-proxy");
  if (dock) {
    const running = !!model.core?.running;
    const busy = model.busy.start || model.busy.stop;
    const tone = running ? "positive" : configurationReady(model) ? "accent" : "warning";
    const title = !model.bootstrapped
      ? "正在准备"
      : running
        ? "本地代理运行中"
        : model.busy.start
          ? "正在启动代理"
          : model.busy.stop
            ? "正在停止代理"
            : "本地代理未启动";
    const action =
      running || model.busy.start
        ? `<button type="button" class="btn btn-sm btn-dock" data-action="stop-core" ${model.busy.stop || model.busy.start ? "disabled" : ""}>${model.busy.stop ? "停止中" : "停止代理"}</button>`
        : `<button type="button" class="btn btn-sm btn-dock btn-primary" data-action="start-core" ${!canStartProxy(model) || busy ? "disabled" : ""}>${model.busy.start ? "启动中" : "启动代理"}</button>`;
    dock.innerHTML = `
      <div class="dock-status tone-${tone}">${escapeHtml(title)}</div>
      <div class="dock-endpoint mono">127.0.0.1:${model.mixedPort}</div>
      ${action}`;
  }

  const host = document.querySelector<HTMLDivElement>("#notice-host");
  if (host) {
    if (!model.notice) {
      host.hidden = true;
      host.innerHTML = "";
    } else {
      host.hidden = false;
      const tone = model.notice.style;
      const actionBtn =
        model.notice.action === "openSettings"
          ? `<button type="button" class="btn btn-ghost btn-sm" data-action="goto-settings">打开设置</button>`
          : model.notice.action === "gotoNodes"
            ? `<button type="button" class="btn btn-ghost btn-sm" data-action="goto-nodes">去选节点</button>`
            : model.notice.action === "gotoProfiles"
              ? `<button type="button" class="btn btn-ghost btn-sm" data-action="goto-profiles">去配置</button>`
              : "";
      host.innerHTML = `
        <div class="notice tone-${tone}">
          <span class="notice-icon">${icon(tone === "error" ? "warn" : tone === "success" ? "check" : "info", 16)}</span>
          <span class="notice-msg">${escapeHtml(model.notice.message)}</span>
          ${actionBtn}
          <button type="button" class="icon-btn" data-action="dismiss-notice" aria-label="关闭">${icon("x", 14)}</button>
        </div>`;
    }
  }

  const modal = document.querySelector<HTMLDivElement>("#modal-host");
  if (modal) {
    if (!model.confirm) {
      modal.hidden = true;
      modal.innerHTML = "";
    } else {
      modal.hidden = false;
      modal.innerHTML = `
        <div class="modal-backdrop" data-action="cancel-confirm"></div>
        <div class="modal" role="dialog" aria-modal="true">
          <h2 class="modal-title">${escapeHtml(model.confirm.title)}</h2>
          <p class="modal-body">${escapeHtml(model.confirm.message)}</p>
          <div class="modal-actions">
            <button type="button" class="btn" data-action="cancel-confirm">取消</button>
            <button type="button" class="btn btn-primary" data-action="confirm-dialog">${escapeHtml(model.confirm.confirmLabel)}</button>
          </div>
        </div>`;
    }
  }
}

/** Soft-update traffic widgets without full section repaint. */
export function patchTrafficWidgets(model: AppModel, root: HTMLElement): void {
  const traffic = model.traffic;
  if (!traffic) return;
  const running = !!model.core?.running;
  const set = (key: string, text: string) => {
    const el = root.querySelector(`[data-metric="${key}"]`);
    if (el) el.textContent = text;
  };
  set("up", traffic.live ? formatRate(traffic.upBps) : "—");
  set("down", traffic.live ? formatRate(traffic.downBps) : "—");
  set("mem", traffic.memoryInUse ? formatBytes(traffic.memoryInUse) : "—");
  set("status", running ? (traffic.live ? "实时采集" : "连接中") : "未连接");
  set("up-total", formatBytes(traffic.uploadTotal));
  set("down-total", formatBytes(traffic.downloadTotal));
  const help = root.querySelector("#traffic-help");
  if (help) {
    help.textContent =
      traffic.message ||
      (running ? "速率 /connections · 内存 /memory" : "启动连接后显示实时流量");
  }
  const sparkHost = root.querySelector("#sparkline-host");
  if (sparkHost && model.trafficHistory.length > 1) {
    const spark = sparklinePaths(model.trafficHistory, 560, 96);
    sparkHost.innerHTML = `<svg class="sparkline" viewBox="0 0 560 96" preserveAspectRatio="none" aria-label="流量曲线">
      <path class="spark-area" d="${spark.areaDown}"></path>
      <path class="spark-down" d="${spark.down}"></path>
      <path class="spark-up" d="${spark.up}"></path>
    </svg>`;
  }
}
