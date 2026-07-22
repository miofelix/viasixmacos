import { icon } from "./icons";
import { escapeHtml, formatBytes, formatRate, formatTime, isLikelyIPv6, truncateMiddle } from "./format";
import {
  configurationReady,
  filteredLogs,
  hasUsableProfile,
  routingModeLabel,
  type AppModel,
} from "./state";
import { ROUTING_MODES, SECTIONS, type AppSection, type RoutingMode } from "./types";

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
      </div>
    </aside>
    <div class="divider-v" aria-hidden="true"></div>
    <main class="detail">
      <div id="detail-content" class="detail-content"></div>
      <div id="notice-host" class="notice-host" hidden></div>
    </main>
  </div>`;
}

export function renderSection(model: AppModel): string {
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

function statusBadge(text: string, tone: "neutral" | "accent" | "positive" | "warning" | "negative"): string {
  return `<span class="badge tone-${tone}">${escapeHtml(text)}</span>`;
}

function stepRow(args: {
  title: string;
  detail: string;
  ready: boolean;
  active: boolean;
  actionLabel?: string;
  actionAttr?: string;
}): string {
  const tone = args.active ? "positive" : args.ready ? "accent" : "warning";
  const mark = args.ready || args.active ? icon("check", 14) : icon("warn", 14);
  const action = args.actionLabel
    ? `<button type="button" class="btn btn-ghost btn-sm" data-action="${args.actionAttr ?? ""}">${escapeHtml(args.actionLabel)}</button>`
    : "";
  return `
  <div class="step-row">
    <div class="step-mark tone-${tone}">${mark}</div>
    <div class="step-body">
      <div class="step-title">${escapeHtml(args.title)}</div>
      <div class="step-detail">${escapeHtml(args.detail)}</div>
    </div>
    ${action}
  </div>`;
}

function renderOverview(model: AppModel): string {
  const running = !!model.core?.running;
  const selectedOk = isLikelyIPv6(model.selectedAddress);
  const profileOk = model.routingMode === "direct" || model.profileYaml.trim().length > 0;
  const virt = model.virtualNetwork;
  const networkReady = virt ? virt.available || !virt.enabled : true;
  const networkActive = running;
  const networkDetail = virt?.enabled
    ? virt.available
      ? "虚拟网卡（Mihomo TUN + Wintun）"
      : "已请求 TUN，但 Wintun 不可用"
    : model.systemProxyEnabled
      ? "系统代理 · 本地 mixed 11451"
      : "用户态本地代理（未启用系统代理 / TUN）";

  const headerTone = running ? "positive" : configurationReady(model) ? "accent" : "warning";
  const headerText = running ? "已连接" : configurationReady(model) ? "就绪" : "待配置";

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

  const entryPrimary = selectedOk ? model.selectedAddress : "未选择有效 IPv6";
  const exitPrimary = model.exitIp?.ip || "尚未检测";
  const exitSecondary = model.exitIp
    ? `${model.exitIp.family} · ${model.exitIp.source}`
    : "点击检测公网出口 IP";

  const actionBtn = running
    ? `<button type="button" class="btn btn-danger" data-action="stop-core" ${model.busy.stop ? "disabled" : ""}>
         ${icon("stop", 16)} <span>${model.busy.stop ? "停止中…" : "断开"}</span>
       </button>`
    : `<button type="button" class="btn btn-primary" data-action="start-core" ${model.busy.start ? "disabled" : ""}>
         ${icon("play", 16)} <span>${model.busy.start ? "启动中…" : "连接"}</span>
       </button>`;

  return `
  ${pageHeader("首页", "IPv6 代理链路状态与控制", statusBadge(headerText, headerTone))}
  <div class="page-scroll">
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
          detail: selectedOk ? model.selectedAddress : "请先在「IPv6 优选」中选择地址",
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
              ? "直连模式 · 无需代理入口"
              : hasUsableProfile(model)
                ? "已加载代理入口 profile"
                : profileOk
                  ? "已有 YAML（示例配置请替换为真实入口）"
                  : "尚未配置 profile",
          ready: profileOk,
          active: profileOk && running,
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
          <p class="help-text muted">当前：${routingModeLabel(model.routingMode)} · 运行中不可切换，请先断开。</p>
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
              <div class="setting-detail">配置 Windows HTTP/HTTPS 代理到 127.0.0.1:11451</div>
            </div>
            <input type="checkbox" id="toggle-sys-proxy" ${model.systemProxyEnabled ? "checked" : ""} ${running ? "disabled" : ""} />
          </label>
          <div class="row-divider"></div>
          <label class="setting-row">
            <div>
              <div class="setting-title">虚拟网卡模式</div>
              <div class="setting-detail">${escapeHtml(virt?.message || "Mihomo TUN + Wintun（通常需管理员）")}</div>
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
        <div class="metric-grid">
          <div class="metric"><div class="metric-label">${icon("arrow-up", 14)} 上传</div><div class="metric-value">${up}</div></div>
          <div class="metric"><div class="metric-label">${icon("arrow-down", 14)} 下载</div><div class="metric-value">${down}</div></div>
          <div class="metric"><div class="metric-label">状态</div><div class="metric-value">${running ? (traffic?.live ? "实时采集" : "连接中") : "未连接"}</div></div>
          <div class="metric"><div class="metric-label">总上传</div><div class="metric-value">${upTotal}</div></div>
          <div class="metric"><div class="metric-label">总下载</div><div class="metric-value">${downTotal}</div></div>
          <div class="metric"><div class="metric-label">Controller</div><div class="metric-value">${model.core?.controllerPort ?? "—"}</div></div>
        </div>
        <p class="help-text muted">${escapeHtml(traffic?.message || (running ? "正在采样 /connections" : "启动代理后显示实时上下行速率"))}</p>
      </div>
    </section>

    <div class="grid-2">
      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("nodes", 16)} <span>IP 信息</span></div>
          <div class="inline-actions">
            <button type="button" class="btn btn-ghost btn-sm" data-action="goto-nodes">选择节点</button>
            <button type="button" class="btn btn-ghost btn-sm" data-action="detect-exit" ${model.busy.exitIp ? "disabled" : ""}>
              ${model.busy.exitIp ? "检测中…" : "检测出口"}
            </button>
          </div>
        </div>
        <div class="card-body stack-12">
          <div class="ip-block">
            <div class="ip-label">IPv6 入口</div>
            <div class="ip-primary mono">${escapeHtml(entryPrimary)}</div>
            <div class="ip-secondary">运行时注入 profile 主代理 server</div>
          </div>
          <div class="row-divider"></div>
          <div class="ip-block">
            <div class="ip-label">公网出口</div>
            <div class="ip-primary mono">${escapeHtml(exitPrimary)}</div>
            <div class="ip-secondary">${escapeHtml(exitSecondary)}</div>
          </div>
        </div>
      </section>

      <section class="card">
        <div class="card-header">
          <div class="card-title">${icon("shield", 16)} <span>应用信息</span></div>
        </div>
        <div class="card-body stack-8">
          <div class="kv"><span>版本</span><span>v${escapeHtml(model.version)}</span></div>
          <div class="kv"><span>平台</span><span>Windows · Tauri 2</span></div>
          <div class="kv"><span>内核</span><span>${running ? `运行中${model.core?.pid != null ? ` · pid ${model.core.pid}` : ""}` : "已停止"}</span></div>
          <div class="kv"><span>系统代理</span><span>${model.proxy?.enabled ? "已启用" : "未启用"}</span></div>
          <p class="help-text muted">产品矩阵与 macOS 对齐：IPv6-first 投影、用户态 Mihomo、可选系统代理与 TUN。</p>
        </div>
      </section>
    </div>
  </div>`;
}

function renderNodes(model: AppModel): string {
  const rows =
    model.speedResults.length === 0
      ? `<tr><td colspan="5" class="empty-cell">暂无测速结果。填写 IP/CIDR 后开始测速。</td></tr>`
      : model.speedResults
          .map((row, index) => {
            const selected = row.ip === model.selectedAddress;
            return `
            <tr class="${selected ? "is-selected" : ""}">
              <td>
                <button type="button" class="linkish" data-select-ip="${escapeHtml(row.ip)}">
                  ${escapeHtml(row.ip)}
                </button>
                ${index === 0 ? `<span class="chip">最佳</span>` : ""}
              </td>
              <td>${escapeHtml(row.latency)}</td>
              <td>${escapeHtml(row.loss)}</td>
              <td>${escapeHtml(row.speed)}</td>
              <td>${escapeHtml(row.region)}</td>
            </tr>`;
          })
          .join("");

  return `
  ${pageHeader(
    "IPv6 优选",
    "测速并选择 IPv6 地址",
    model.selectedAddress
      ? statusBadge(truncateMiddle(model.selectedAddress, 28), isLikelyIPv6(model.selectedAddress) ? "accent" : "warning")
      : statusBadge("未选择", "warning"),
  )}
  <div class="page-scroll">
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("nodes", 16)} <span>测速</span></div>
      </div>
      <div class="card-body">
        <div class="form-row">
          <label class="field grow">
            <span>IP / CIDR（可多个，逗号分隔）</span>
            <input id="speed-ip" type="text" value="${escapeHtml(model.speedIpRange)}" placeholder="2606:4700::/32 或单个 IPv6" />
          </label>
          <label class="check field-align">
            <input id="speed-dd" type="checkbox" ${model.speedDisableDownload ? "checked" : ""} />
            <span>仅延迟（-dd，更快）</span>
          </label>
        </div>
        <div class="inline-actions">
          <button type="button" class="btn btn-primary" data-action="run-speed" ${model.busy.speed ? "disabled" : ""}>
            ${model.busy.speed ? "测速中…" : "开始测速"}
          </button>
          <button type="button" class="btn" data-action="apply-best" ${model.speedResults.length === 0 ? "disabled" : ""}>
            应用最佳结果
          </button>
        </div>
        <p class="help-text" id="speed-status">${escapeHtml(model.speedMessage)}</p>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("logs", 16)} <span>结果</span></div>
        <span class="muted small">${model.speedResults.length} 条</span>
      </div>
      <div class="card-body pad-0">
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>IP</th>
                <th>延迟</th>
                <th>丢包</th>
                <th>速度</th>
                <th>地区</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      </div>
    </section>

    <section class="card soft">
      <div class="card-body">
        <p class="help-text">点击结果中的 IP 即可设为当前入口。当前选中：
          <span class="mono">${escapeHtml(model.selectedAddress || "—")}</span>
        </p>
        <p class="help-text muted">与 macOS「IPv6 优选」一致：测速只负责候选排序；启动时由投影将选中 IPv6 写入主代理 server。</p>
      </div>
    </section>
  </div>`;
}

function renderProfiles(model: AppModel): string {
  const tone = hasUsableProfile(model) || model.routingMode === "direct" ? "positive" : "warning";
  const status =
    model.routingMode === "direct"
      ? "直连"
      : hasUsableProfile(model)
        ? "已配置"
        : model.profileYaml.trim()
          ? "示例/待替换"
          : "未配置";

  return `
  ${pageHeader(
    "连接配置",
    "管理用于承载当前 IPv6 地址的代理入口",
    statusBadge(status, tone),
  )}
  <div class="page-scroll">
    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("profile", 16)} <span>当前代理入口</span></div>
      </div>
      <div class="card-body">
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
        <div class="inline-actions">
          <button type="button" class="btn btn-primary" data-action="project-config" ${model.busy.project ? "disabled" : ""}>
            ${model.busy.project ? "生成中…" : "生成运行配置"}
          </button>
          <button type="button" class="btn" data-action="start-core" ${model.busy.start || model.core?.running ? "disabled" : ""}>
            启动 Mihomo
          </button>
          <button type="button" class="btn" data-action="stop-core" ${model.busy.stop || !model.core?.running ? "disabled" : ""}>
            停止
          </button>
        </div>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("logs", 16)} <span>运行配置预览</span></div>
      </div>
      <div class="card-body pad-0">
        <pre class="code-block" id="runtime-yaml">${escapeHtml(model.runtimeYaml)}</pre>
      </div>
    </section>

    <section class="card soft">
      <div class="card-body stack-8">
        <div class="card-title inline">${icon("shield", 16)} <span>安全说明</span></div>
        <p class="help-text">导入 YAML 中的 Controller、TUN、监听等字段不会进入运行配置；仅投影后的单 IPv6 主代理（或直连规则）会交给 Mihomo。</p>
        <p class="help-text muted">与 macOS / contracts 对齐：Provider-only 与 IPv4 选择会被拒绝。</p>
      </div>
    </section>
  </div>`;
}

function renderLogs(model: AppModel): string {
  const visible = filteredLogs(model).slice().reverse();
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
    `<button type="button" class="btn btn-ghost btn-sm" data-action="clear-logs" ${model.logs.length === 0 ? "disabled" : ""}>
       ${icon("trash", 14)} 清空
     </button>`,
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
        <p class="help-text muted">${visible.length} / ${model.logs.length} 条（客户端会话日志）</p>
      </div>
    </section>
    <section class="card">
      <div class="card-body pad-0 log-list">${rows}</div>
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

  return `
  ${pageHeader("设置", "连接、网络接入与运行组件")}
  <div class="page-scroll">
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
            <div class="setting-detail">${escapeHtml(model.controller?.message || "尚未探测")}</div>
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
            <button type="button" class="btn btn-sm" data-action="apply-sys-proxy">应用</button>
            <button type="button" class="btn btn-sm" data-action="clear-sys-proxy">清除</button>
          </div>
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
        <p class="help-text muted">Windows 使用进程内 Mihomo TUN + Wintun.dll（通常需管理员）。与 macOS 特权 LaunchDaemon 路径不同，但产品开关语义一致：可与系统代理同时启用。</p>
        <label class="check">
          <input type="checkbox" id="settings-virt-net" ${model.virtualNetworkEnabled ? "checked" : ""} ${virt && !virt.available ? "disabled" : ""} />
          <span>启用虚拟网卡（下次启动 Mihomo 时生效）</span>
        </label>
      </div>
    </section>

    <section class="card">
      <div class="card-header">
        <div class="card-title">${icon("info", 16)} <span>关于</span></div>
      </div>
      <div class="card-body stack-8">
        <div class="kv"><span>应用</span><span>ViaSix for Windows</span></div>
        <div class="kv"><span>版本</span><span>v${escapeHtml(model.version)}</span></div>
        <div class="kv"><span>本地 mixed</span><span>127.0.0.1:11451</span></div>
        <div class="kv"><span>投影契约</span><span>contracts/fixtures/mihomo-config</span></div>
        <p class="help-text muted">UI 信息架构对齐 macOS：首页 · IPv6 优选 · 连接配置 · 日志 · 设置。</p>
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

  const host = document.querySelector<HTMLDivElement>("#notice-host");
  if (!host) return;
  if (!model.notice) {
    host.hidden = true;
    host.innerHTML = "";
    return;
  }
  host.hidden = false;
  const tone = model.notice.style;
  host.innerHTML = `
    <div class="notice tone-${tone}">
      <span class="notice-icon">${icon(tone === "error" ? "warn" : tone === "success" ? "check" : "info", 16)}</span>
      <span class="notice-msg">${escapeHtml(model.notice.message)}</span>
      ${
        model.notice.action === "openSettings"
          ? `<button type="button" class="btn btn-ghost btn-sm" data-action="goto-settings">打开设置</button>`
          : ""
      }
      <button type="button" class="icon-btn" data-action="dismiss-notice" aria-label="关闭">${icon("x", 14)}</button>
    </div>`;
}
