mod activity_log;
mod connectivity;
mod controller;
mod exit_ip;
mod ip_lists;
mod prefs;
mod profile;
mod profile_store;
mod projection;
mod runtime;
mod speed_test;
mod system_proxy;
mod traffic;
mod tray_presentation;
mod virtual_network;

use activity_log::{ActivityEntry, ActivityLog};
use connectivity::ConnectivityResult;
use controller::ControllerHealth;
use parking_lot::Mutex;
use prefs::{PrefsStore, SessionPrefs};
use profile::ProfileSummary;
use projection::{ProjectOptions, RoutingMode, TunOptions};
use runtime::{CoreRuntime, CoreStatus, SharedCore};
use speed_test::{IpPreset, SpeedTestRequest, SpeedTestResponse, SpeedTestSession};
use std::path::PathBuf;
use std::sync::Arc;
use system_proxy::{ProxyEndpoint, SystemProxyManager, SystemProxyStatus};
use traffic::{TrafficSampler, TrafficSnapshot};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, RunEvent, State, WindowEvent,
};
use tray_presentation::tray_menu_presentation;
use virtual_network::{
    stage_wintun_beside_mihomo, TunPreflight, VirtualNetworkCapability, VirtualNetworkManager,
    VirtualNetworkStatus,
};

/// Keeps tray menu items so labels/enabled can track proxy state (macOS menu-bar style).
struct TrayMenuItems {
    status: MenuItem<tauri::Wry>,
    start: MenuItem<tauri::Wry>,
    stop: MenuItem<tauri::Wry>,
}

struct AppServices {
    core: SharedCore,
    system_proxy: SystemProxyManager,
    prefs: PrefsStore,
    virtual_network: Mutex<VirtualNetworkManager>,
    traffic: Mutex<TrafficSampler>,
    activity: Mutex<ActivityLog>,
    speed_test: SpeedTestSession,
    default_mixed_port: u16,
    data_dir: PathBuf,
}

type SharedServices = Arc<AppServices>;

fn push_log(
    services: &AppServices,
    app: Option<&AppHandle>,
    level: &str,
    source: &str,
    message: impl Into<String>,
) {
    let entry = services.activity.lock().push(level, source, message);
    if let Some(app) = app {
        let _ = app.emit("activity-log", &entry);
    }
}

fn apply_ports(options: &mut ProjectOptions, mixed_port: Option<u16>, controller_port: Option<u16>) {
    if let Some(port) = mixed_port.filter(|p| *p > 0) {
        options.mixed_port = port;
    }
    if let Some(port) = controller_port.filter(|p| *p > 0) {
        options.controller_port = port;
    }
}

fn apply_proxy_flags(
    options: &mut ProjectOptions,
    udp_enabled: Option<bool>,
    sniffing_enabled: Option<bool>,
) {
    if let Some(v) = udp_enabled {
        options.udp_enabled = v;
    }
    if let Some(v) = sniffing_enabled {
        options.sniffing_enabled = v;
    }
}

fn refresh_tray_chrome(app: &AppHandle, running: bool, snap: Option<&TrafficSnapshot>) {
    let (up, down) = snap
        .filter(|s| s.live)
        .map(|s| (Some(s.up_bps), Some(s.down_bps)))
        .unwrap_or((None, None));
    let presentation = tray_menu_presentation(running, up, down);
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_tooltip(Some(presentation.tooltip.as_str()));
    }
    if let Some(items) = app.try_state::<TrayMenuItems>() {
        let _ = items.status.set_text(presentation.status_label);
        let _ = items.start.set_text(presentation.start_label);
        let _ = items.start.set_enabled(presentation.start_enabled);
        let _ = items.stop.set_text(presentation.stop_label);
        let _ = items.stop.set_enabled(presentation.stop_enabled);
    }
}

#[tauri::command]
fn project_runtime_config(
    profile_yaml: String,
    selected_address: Option<String>,
    routing_mode: String,
    mixed_port: Option<u16>,
    controller_port: Option<u16>,
    udp_enabled: Option<bool>,
    sniffing_enabled: Option<bool>,
) -> Result<String, String> {
    let mode = RoutingMode::parse(&routing_mode).ok_or_else(|| "invalid routingMode".to_string())?;
    let mut options = ProjectOptions::default();
    options.routing_mode = mode;
    options.selected_address = selected_address;
    apply_ports(&mut options, mixed_port, controller_port);
    apply_proxy_flags(&mut options, udp_enabled, sniffing_enabled);
    let profile = if mode == RoutingMode::Direct {
        None
    } else {
        Some(profile_yaml.as_str())
    };
    projection::project_runtime_yaml(profile, &options).map_err(|e| e.to_string())
}

#[tauri::command]
fn summarize_profile(profile_yaml: String) -> ProfileSummary {
    profile::summarize_profile_yaml(&profile_yaml)
}

#[tauri::command]
fn read_text_file(path: String) -> Result<String, String> {
    let p = PathBuf::from(&path);
    if !p.is_file() {
        return Err(format!("file not found: {path}"));
    }
    // Basic guard: only allow reasonable text sizes for profile YAML.
    let meta = std::fs::metadata(&p).map_err(|e| e.to_string())?;
    if meta.len() > 2 * 1024 * 1024 {
        return Err("file too large (max 2 MiB)".into());
    }
    std::fs::read_to_string(&p).map_err(|e| e.to_string())
}

#[tauri::command]
fn core_status(services: State<'_, SharedServices>) -> CoreStatus {
    services.core.status()
}

#[tauri::command]
fn start_core(
    app: AppHandle,
    services: State<'_, SharedServices>,
    profile_yaml: String,
    selected_address: Option<String>,
    routing_mode: String,
    enable_system_proxy: Option<bool>,
    mixed_port: Option<u16>,
    controller_port: Option<u16>,
    tun_stack: Option<String>,
    tun_mtu: Option<u16>,
    udp_enabled: Option<bool>,
    sniffing_enabled: Option<bool>,
) -> Result<CoreStatus, String> {
    let mode = RoutingMode::parse(&routing_mode).ok_or_else(|| "invalid routingMode".to_string())?;
    let mut options = ProjectOptions::default();
    options.routing_mode = mode;
    options.selected_address = selected_address;
    apply_ports(&mut options, mixed_port, controller_port);
    apply_proxy_flags(&mut options, udp_enabled, sniffing_enabled);

    let want_tun = services.virtual_network.lock().is_enabled();
    if want_tun {
        let pre = services.virtual_network.lock().preflight();
        if !pre.ready {
            push_log(
                &services,
                Some(&app),
                "error",
                "network",
                pre.message.clone(),
            );
            return Err(pre.message);
        }
        let mut tun = TunOptions::default();
        if let Some(stack) = tun_stack
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
        {
            tun.stack = stack;
        }
        if let Some(mtu) = tun_mtu.filter(|m| (1280..=9000).contains(m)) {
            tun.mtu = mtu;
        }
        options.tun = Some(tun);
    }

    // Project first so failures never leave a half-started process.
    let profile = if mode == RoutingMode::Direct {
        None
    } else {
        Some(profile_yaml.as_str())
    };
    let _preview = projection::project_runtime_yaml(profile, &options).map_err(|e| {
        let msg = e.to_string();
        push_log(
            &services,
            Some(&app),
            "error",
            "config",
            format!("投影失败: {msg}"),
        );
        msg
    })?;

    let bin = resolve_mihomo_binary(&app).map_err(|e| {
        push_log(&services, Some(&app), "error", "core", e.clone());
        e
    })?;
    if want_tun {
        let sidecar = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("sidecar");
        stage_wintun_beside_mihomo(&bin, &sidecar).map_err(|e| {
            push_log(&services, Some(&app), "error", "network", e.clone());
            e
        })?;
    }

    push_log(
        &services,
        Some(&app),
        "info",
        "core",
        format!(
            "正在启动 Mihomo (mode={}, mixed={}:{}, controller={})",
            mode.as_str(),
            options.listen_address,
            options.mixed_port,
            options.controller_port
        ),
    );

    let mut status = services.core.start(profile, &options, &bin).map_err(|e| {
        push_log(&services, Some(&app), "error", "core", e.clone());
        e
    })?;
    services.traffic.lock().reset();
    if want_tun {
        status.message = format!(
            "{}; TUN/Wintun requested (admin may be required)",
            status.message
        );
    }

    if enable_system_proxy.unwrap_or(false) {
        let endpoint = ProxyEndpoint {
            host: options.listen_address.clone(),
            port: options.mixed_port,
        };
        match services.system_proxy.enable(&endpoint) {
            Ok(proxy_status) => {
                status.message = format!("{}; {}", status.message, proxy_status.message);
                push_log(
                    &services,
                    Some(&app),
                    "info",
                    "proxy",
                    proxy_status.message.clone(),
                );
            }
            Err(err) => {
                status.message =
                    format!("{}; system proxy not applied: {err}", status.message);
                push_log(
                    &services,
                    Some(&app),
                    "warn",
                    "proxy",
                    format!("系统代理未应用: {err}"),
                );
            }
        }
    }

    push_log(
        &services,
        Some(&app),
        if status.running { "success" } else { "warn" },
        "core",
        status.message.clone(),
    );
    refresh_tray_chrome(&app, status.running, None);
    Ok(status)
}

#[tauri::command]
fn stop_core(app: AppHandle, services: State<'_, SharedServices>) -> Result<CoreStatus, String> {
    let status = services.core.stop().map_err(|e| {
        push_log(&services, Some(&app), "error", "core", e.clone());
        e
    })?;
    services.traffic.lock().reset();
    let proxy_note = match services.system_proxy.disable() {
        Ok(s) => {
            push_log(&services, Some(&app), "info", "proxy", s.message.clone());
            s.message
        }
        Err(err) => {
            let msg = format!("system proxy restore failed: {err}");
            push_log(&services, Some(&app), "warn", "proxy", msg.clone());
            msg
        }
    };
    let message = format!("{}; {proxy_note}", status.message);
    push_log(&services, Some(&app), "info", "core", message.clone());
    refresh_tray_chrome(&app, false, None);
    Ok(CoreStatus {
        running: status.running,
        pid: status.pid,
        message,
        controller_port: status.controller_port,
    })
}

#[tauri::command]
fn system_proxy_status(services: State<'_, SharedServices>) -> SystemProxyStatus {
    services.system_proxy.status()
}

#[tauri::command]
fn set_system_proxy(
    app: AppHandle,
    services: State<'_, SharedServices>,
    enabled: bool,
    host: Option<String>,
    port: Option<u16>,
) -> Result<SystemProxyStatus, String> {
    let result = if enabled {
        let endpoint = ProxyEndpoint {
            host: host.unwrap_or_else(|| "127.0.0.1".into()),
            port: port.unwrap_or(services.default_mixed_port),
        };
        services.system_proxy.enable(&endpoint)
    } else {
        services.system_proxy.disable()
    };
    match &result {
        Ok(status) => push_log(&services, Some(&app), "info", "proxy", status.message.clone()),
        Err(err) => push_log(
            &services,
            Some(&app),
            "error",
            "proxy",
            format!("系统代理操作失败: {err}"),
        ),
    }
    result
}

#[tauri::command]
async fn detect_exit_ip(
    app: AppHandle,
    services: State<'_, SharedServices>,
    endpoints: Option<Vec<String>>,
) -> Result<exit_ip::ExitIpResult, String> {
    match exit_ip::detect_exit_ip(endpoints).await {
        Ok(result) => {
            push_log(
                &services,
                Some(&app),
                "success",
                "network",
                format!("{} ({})", result.message, result.source),
            );
            Ok(result)
        }
        Err(err) => {
            push_log(
                &services,
                Some(&app),
                "error",
                "network",
                format!("出口检测失败: {err}"),
            );
            Err(err)
        }
    }
}

fn resolve_cfst(app: &AppHandle) -> Result<PathBuf, String> {
    resolve_bundled_binary(app, "viasix-cfst").or_else(|_| {
        let sidecar = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("sidecar");
        speed_test::resolve_cfst_binary(&sidecar)
    })
}

#[tauri::command]
fn run_speed_test(
    app: AppHandle,
    services: State<'_, SharedServices>,
    mut request: SpeedTestRequest,
    use_bundled_list: Option<bool>,
) -> Result<SpeedTestResponse, String> {
    if use_bundled_list.unwrap_or(false) {
        let path = ip_lists::ensure_ipv6_list(&services.data_dir).map_err(|e| {
            push_log(&services, Some(&app), "error", "speed", e.clone());
            e
        })?;
        request.ip_file = Some(path.display().to_string());
        request.ip_range = None;
        push_log(
            &services,
            Some(&app),
            "info",
            "speed",
            format!("开始 CFST 测速（内置 IPv6 列表 {}）…", path.display()),
        );
    } else {
        push_log(&services, Some(&app), "info", "speed", "开始 CFST 测速…");
    }
    let bin = resolve_cfst(&app).map_err(|e| {
        push_log(&services, Some(&app), "error", "speed", e.clone());
        e
    })?;
    let work = services.data_dir.join("cfst");
    match services.speed_test.run(&bin, &work, &request) {
        Ok(response) => {
            let level = if response.cancelled { "warn" } else { "success" };
            push_log(&services, Some(&app), level, "speed", response.message.clone());
            Ok(response)
        }
        Err(err) => {
            push_log(
                &services,
                Some(&app),
                "error",
                "speed",
                format!("测速失败: {err}"),
            );
            Err(err)
        }
    }
}

#[tauri::command]
fn stop_speed_test(app: AppHandle, services: State<'_, SharedServices>) -> Result<bool, String> {
    let cancelled = services.speed_test.request_cancel();
    if cancelled {
        push_log(&services, Some(&app), "warn", "speed", "正在停止测速…");
    }
    Ok(cancelled)
}

#[tauri::command]
fn speed_test_running(services: State<'_, SharedServices>) -> bool {
    services.speed_test.is_running()
}

/// macOS-style current-node configuration test (CFST against selected IPv6 only).
#[tauri::command]
fn test_current_node(
    app: AppHandle,
    services: State<'_, SharedServices>,
    selected_address: String,
    disable_download: Option<bool>,
    threads: Option<u32>,
    ping_count: Option<u32>,
    port: Option<u16>,
) -> Result<SpeedTestResponse, String> {
    let ip = selected_address.trim().to_string();
    if ip.is_empty() || !ip.contains(':') {
        return Err("selectedAddress must be an IPv6 address".into());
    }
    push_log(
        &services,
        Some(&app),
        "info",
        "speed",
        format!("开始测试当前节点：{ip}"),
    );
    let request = SpeedTestRequest {
        ip_range: Some(ip.clone()),
        ip_file: None,
        threads: Some(threads.unwrap_or(50)),
        ping_count: Some(ping_count.unwrap_or(4)),
        download_count: Some(3),
        download_time: Some(3),
        disable_download: Some(disable_download.unwrap_or(true)),
        httping: Some(true),
        port: Some(port.unwrap_or(443)),
    };
    let bin = resolve_cfst(&app)?;
    let work = services.data_dir.join("cfst-node");
    match services.speed_test.run(&bin, &work, &request) {
        Ok(mut response) => {
            if !response.cancelled {
                // Prefer exact match when present.
                if let Some(idx) = response.results.iter().position(|r| r.ip == ip) {
                    let matched = response.results.swap_remove(idx);
                    response.results = vec![matched];
                } else if let Some(first) = response.results.first_mut() {
                    first.ip = ip;
                }
                response.message = format!(
                    "当前节点测速完成: {}",
                    response
                        .results
                        .first()
                        .map(|r| format!("{} ms / loss {}", r.latency, r.loss))
                        .unwrap_or_else(|| "无结果".into())
                );
            }
            let level = if response.cancelled {
                "warn"
            } else {
                "success"
            };
            push_log(&services, Some(&app), level, "speed", response.message.clone());
            Ok(response)
        }
        Err(err) => {
            push_log(
                &services,
                Some(&app),
                "error",
                "speed",
                format!("当前节点测速失败: {err}"),
            );
            Err(err)
        }
    }
}

#[tauri::command]
fn list_ip_presets() -> Vec<IpPreset> {
    speed_test::ipv6_presets()
}

#[tauri::command]
async fn probe_connectivity(
    app: AppHandle,
    services: State<'_, SharedServices>,
    mixed_port: Option<u16>,
    url: Option<String>,
) -> Result<ConnectivityResult, String> {
    if !services.core.status().running {
        return Err("Mihomo is not running".into());
    }
    let port = mixed_port.unwrap_or(services.default_mixed_port);
    push_log(
        &services,
        Some(&app),
        "info",
        "network",
        format!("探测代理连通性 127.0.0.1:{port}…"),
    );
    match connectivity::probe_via_proxy("127.0.0.1", port, url).await {
        Ok(result) => {
            push_log(
                &services,
                Some(&app),
                if result.ok { "success" } else { "warn" },
                "network",
                result.message.clone(),
            );
            Ok(result)
        }
        Err(err) => {
            push_log(
                &services,
                Some(&app),
                "error",
                "network",
                format!("代理连通性失败: {err}"),
            );
            Err(err)
        }
    }
}

#[tauri::command]
fn tail_core_log(services: State<'_, SharedServices>, max_lines: Option<usize>) -> Result<String, String> {
    services.core.tail_log(max_lines.unwrap_or(200))
}

#[tauri::command]
fn load_session_prefs(services: State<'_, SharedServices>) -> SessionPrefs {
    services.prefs.load()
}

#[tauri::command]
fn save_session_prefs(
    services: State<'_, SharedServices>,
    prefs: SessionPrefs,
) -> Result<(), String> {
    services.prefs.save(&prefs)
}

#[tauri::command]
fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tauri::command]
fn data_dir_path(services: State<'_, SharedServices>) -> String {
    services.data_dir.display().to_string()
}

#[tauri::command]
fn open_data_dir(services: State<'_, SharedServices>) -> Result<String, String> {
    // Return path so the frontend can open it via shell plugin (opener path).
    Ok(services.data_dir.display().to_string())
}

#[tauri::command]
fn list_activity_logs(services: State<'_, SharedServices>) -> Vec<ActivityEntry> {
    services.activity.lock().list()
}

#[tauri::command]
fn clear_activity_logs(app: AppHandle, services: State<'_, SharedServices>) {
    services.activity.lock().clear();
    push_log(&services, Some(&app), "info", "app", "活动日志已清空");
}

#[tauri::command]
async fn probe_controller(
    app: AppHandle,
    services: State<'_, SharedServices>,
) -> Result<ControllerHealth, String> {
    let Some((port, secret)) = services.core.controller_credentials() else {
        let health = ControllerHealth {
            ok: false,
            endpoint: String::new(),
            message: "Mihomo is not running".into(),
            version: None,
        };
        push_log(&services, Some(&app), "warn", "core", health.message.clone());
        return Ok(health);
    };
    let health = controller::probe("127.0.0.1", port, &secret).await;
    push_log(
        &services,
        Some(&app),
        if health.ok { "success" } else { "warn" },
        "core",
        health.message.clone(),
    );
    Ok(health)
}

#[tauri::command]
async fn sample_traffic(
    app: AppHandle,
    services: State<'_, SharedServices>,
) -> Result<TrafficSnapshot, String> {
    let running = services.core.status().running;
    let Some((port, secret)) = services.core.controller_credentials() else {
        services.traffic.lock().reset();
        refresh_tray_chrome(&app, running, None);
        return Ok(TrafficSnapshot {
            live: false,
            up_bps: 0,
            down_bps: 0,
            upload_total: 0,
            download_total: 0,
            memory_in_use: 0,
            message: "Mihomo is not running".into(),
        });
    };

    let mut sampler = {
        let mut guard = services.traffic.lock();
        std::mem::take(&mut *guard)
    };
    let snap = sampler.sample("127.0.0.1", port, &secret).await;
    *services.traffic.lock() = sampler;
    refresh_tray_chrome(&app, true, Some(&snap));
    Ok(snap)
}

#[tauri::command]
fn ensure_ipv6_list(services: State<'_, SharedServices>) -> Result<String, String> {
    ip_lists::ensure_ipv6_list(&services.data_dir).map(|p| p.display().to_string())
}

#[tauri::command]
fn reset_ipv6_list(app: AppHandle, services: State<'_, SharedServices>) -> Result<String, String> {
    let path = ip_lists::reset_ipv6_list(&services.data_dir)?;
    push_log(
        &services,
        Some(&app),
        "info",
        "speed",
        format!("已重置内置 IPv6 列表：{}", path.display()),
    );
    Ok(path.display().to_string())
}

#[tauri::command]
fn read_ipv6_list(services: State<'_, SharedServices>) -> Result<String, String> {
    ip_lists::read_ipv6_list(&services.data_dir)
}

#[tauri::command]
fn load_profile_file(services: State<'_, SharedServices>) -> Result<Option<String>, String> {
    profile_store::load_profile(&services.data_dir)
}

#[tauri::command]
fn save_profile_file(
    app: AppHandle,
    services: State<'_, SharedServices>,
    profile_yaml: String,
) -> Result<String, String> {
    let path = profile_store::save_profile(&services.data_dir, &profile_yaml)?;
    push_log(
        &services,
        Some(&app),
        "success",
        "config",
        format!("已保存 profile.yaml → {path}"),
    );
    Ok(path)
}

#[tauri::command]
fn virtual_network_capability(services: State<'_, SharedServices>) -> VirtualNetworkCapability {
    services.virtual_network.lock().capability()
}

#[tauri::command]
fn virtual_network_status(services: State<'_, SharedServices>) -> VirtualNetworkStatus {
    services.virtual_network.lock().status()
}

#[tauri::command]
fn set_virtual_network(
    app: AppHandle,
    services: State<'_, SharedServices>,
    enabled: bool,
) -> Result<VirtualNetworkStatus, String> {
    // Single lock scope: parking_lot::Mutex is not re-entrant.
    let (result, preflight) = {
        let mut mgr = services.virtual_network.lock();
        let result = if enabled {
            mgr.enable()
        } else {
            mgr.disable()
        };
        let preflight = result.as_ref().ok().map(|_| mgr.preflight());
        (result, preflight)
    };
    match &result {
        Ok(status) => {
            push_log(
                &services,
                Some(&app),
                "info",
                "network",
                status.message.clone(),
            );
            if let Some(pre) = preflight {
                push_log(
                    &services,
                    Some(&app),
                    if pre.ready { "info" } else { "warn" },
                    "network",
                    pre.message.clone(),
                );
            }
        }
        Err(err) => push_log(
            &services,
            Some(&app),
            "error",
            "network",
            format!("虚拟网卡切换失败: {err}"),
        ),
    }
    result
}

#[tauri::command]
fn tun_preflight(services: State<'_, SharedServices>) -> TunPreflight {
    services.virtual_network.lock().preflight()
}

fn resolve_mihomo_binary(app: &AppHandle) -> Result<PathBuf, String> {
    resolve_bundled_binary(app, "viasix-mihomo")
}

fn resolve_bundled_binary(app: &AppHandle, stem: &str) -> Result<PathBuf, String> {
    let resource_candidates = [
        format!("sidecar/{stem}"),
        format!("sidecar/{stem}.exe"),
        stem.to_string(),
        format!("{stem}.exe"),
    ];
    for rel in resource_candidates {
        if let Ok(path) = app
            .path()
            .resolve(&rel, tauri::path::BaseDirectory::Resource)
        {
            if path.is_file() {
                return Ok(path);
            }
        }
    }

    let mut dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dev.push("sidecar");
    let plain_name = if cfg!(windows) {
        format!("{stem}.exe")
    } else {
        stem.to_string()
    };
    let plain = dev.join(&plain_name);
    if plain.is_file() {
        return Ok(plain);
    }

    if let Ok(entries) = std::fs::read_dir(&dev) {
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if file_name.starts_with(stem) && path.is_file() {
                return Ok(path);
            }
        }
    }

    Err(format!(
        "{stem} binary not found under {}. Run `pnpm prebuild`.",
        dev.display()
    ))
}

fn default_data_dir(app: &AppHandle) -> PathBuf {
    app.path()
        .app_data_dir()
        .unwrap_or_else(|_| std::env::temp_dir().join("viasix-windows"))
}

fn shutdown_services(services: &AppServices) {
    let _ = services.core.stop();
    services.traffic.lock().reset();
    let _ = services.system_proxy.disable();
    push_log(services, None, "info", "app", "应用退出：已停止内核并尝试恢复系统代理");
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let presentation = tray_menu_presentation(false, None, None);
    let show_i = MenuItem::with_id(app, "show", "显示 ViaSix", true, None::<&str>)?;
    let status_i =
        MenuItem::with_id(app, "status", presentation.status_label.as_str(), false, None::<&str>)?;
    let start_i = MenuItem::with_id(
        app,
        "start",
        presentation.start_label.as_str(),
        presentation.start_enabled,
        None::<&str>,
    )?;
    let stop_i = MenuItem::with_id(
        app,
        "stop",
        presentation.stop_label.as_str(),
        presentation.stop_enabled,
        None::<&str>,
    )?;
    let quit_i = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show_i, &status_i, &start_i, &stop_i, &quit_i])?;

    app.manage(TrayMenuItems {
        status: status_i,
        start: start_i,
        stop: stop_i,
    });

    let icon = app
        .default_window_icon()
        .cloned()
        .ok_or_else(|| tauri::Error::FailedToReceiveMessage)?;

    TrayIconBuilder::with_id("main")
        .icon(icon)
        .menu(&menu)
        .tooltip(presentation.tooltip)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" | "status" => show_main_window(app),
            "start" => {
                let running = app
                    .try_state::<SharedServices>()
                    .map(|s| s.core.status().running)
                    .unwrap_or(false);
                if running {
                    return;
                }
                // Frontend owns full start payload; tray focuses UI and requests start.
                let _ = app.emit("tray-action", "start");
                show_main_window(app);
            }
            "stop" => {
                if let Some(services) = app.try_state::<SharedServices>() {
                    match services.core.stop() {
                        Ok(status) => {
                            services.traffic.lock().reset();
                            let _ = services.system_proxy.disable();
                            push_log(
                                services.inner(),
                                Some(app),
                                "info",
                                "core",
                                format!("托盘停止: {}", status.message),
                            );
                            refresh_tray_chrome(app, false, None);
                            let _ = app.emit("core-stopped", status);
                        }
                        Err(err) => push_log(
                            services.inner(),
                            Some(app),
                            "error",
                            "core",
                            format!("托盘停止失败: {err}"),
                        ),
                    }
                }
            }
            "quit" => {
                if let Some(services) = app.try_state::<SharedServices>() {
                    shutdown_services(services.inner());
                }
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                show_main_window(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let data = default_data_dir(app.handle());
            let work = data.join("runtime");
            let sidecar = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("sidecar");
            let defaults = ProjectOptions::default();
            let services = Arc::new(AppServices {
                core: Arc::new(CoreRuntime::new(work)),
                system_proxy: SystemProxyManager::new(data.clone()),
                prefs: PrefsStore::new(data.clone()),
                virtual_network: Mutex::new(VirtualNetworkManager::new(sidecar)),
                traffic: Mutex::new(TrafficSampler::default()),
                activity: Mutex::new(ActivityLog::new(800)),
                speed_test: SpeedTestSession::default(),
                default_mixed_port: defaults.mixed_port,
                data_dir: data,
            });
            // Recover any leftover system proxy from a previous crash.
            let recovered = services.system_proxy.disable();
            if let Ok(status) = recovered {
                if status.message.contains("restored") || status.message.contains("cleared") {
                    push_log(
                        &services,
                        None,
                        "info",
                        "proxy",
                        format!("启动恢复: {}", status.message),
                    );
                }
            }
            // Install managed ipv6 list into app data (macOS ships Resources/ipv6.txt).
            if let Err(err) = ip_lists::ensure_ipv6_list(&services.data_dir) {
                eprintln!("ipv6 list install failed: {err}");
            }
            push_log(&services, None, "info", "app", "ViaSix Windows 后端已就绪");
            app.manage(services);

            if let Err(err) = setup_tray(app.handle()) {
                eprintln!("tray setup failed: {err}");
            } else {
                refresh_tray_chrome(app.handle(), false, None);
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                let close_to_tray = window
                    .app_handle()
                    .try_state::<SharedServices>()
                    .map(|s| s.prefs.load().close_to_tray.unwrap_or(true))
                    .unwrap_or(true);
                if close_to_tray {
                    api.prevent_close();
                    let _ = window.hide();
                    if let Some(services) = window.app_handle().try_state::<SharedServices>() {
                        push_log(
                            services.inner(),
                            Some(window.app_handle()),
                            "info",
                            "app",
                            "窗口已隐藏到托盘（关闭时退出可在设置中关闭）",
                        );
                    }
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            project_runtime_config,
            summarize_profile,
            read_text_file,
            core_status,
            start_core,
            stop_core,
            system_proxy_status,
            set_system_proxy,
            detect_exit_ip,
            run_speed_test,
            stop_speed_test,
            speed_test_running,
            test_current_node,
            list_ip_presets,
            ensure_ipv6_list,
            reset_ipv6_list,
            read_ipv6_list,
            load_profile_file,
            save_profile_file,
            probe_connectivity,
            tail_core_log,
            load_session_prefs,
            save_session_prefs,
            app_version,
            data_dir_path,
            open_data_dir,
            list_activity_logs,
            clear_activity_logs,
            probe_controller,
            sample_traffic,
            virtual_network_capability,
            virtual_network_status,
            set_virtual_network,
            tun_preflight
        ])
        .build(tauri::generate_context!())
        .expect("error while building ViaSix Windows")
        .run(|app_handle, event| {
            if let RunEvent::Exit = event {
                if let Some(services) = app_handle.try_state::<SharedServices>() {
                    shutdown_services(services.inner());
                }
            }
        });
}
