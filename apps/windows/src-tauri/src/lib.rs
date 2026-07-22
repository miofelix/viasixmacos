mod controller;
mod exit_ip;
mod prefs;
mod projection;
mod runtime;
mod speed_test;
mod system_proxy;
mod traffic;
mod virtual_network;

use controller::ControllerHealth;
use parking_lot::Mutex;
use prefs::{PrefsStore, SessionPrefs};
use projection::{ProjectOptions, RoutingMode};
use runtime::{CoreStatus, CoreRuntime, SharedCore};
use speed_test::{SpeedTestRequest, SpeedTestResponse};
use std::path::PathBuf;
use std::sync::Arc;
use system_proxy::{ProxyEndpoint, SystemProxyManager, SystemProxyStatus};
use traffic::{TrafficSampler, TrafficSnapshot};
use tauri::{AppHandle, Manager, State};
use virtual_network::{
    VirtualNetworkCapability, VirtualNetworkManager, VirtualNetworkStatus,
};

struct AppServices {
    core: SharedCore,
    system_proxy: SystemProxyManager,
    prefs: PrefsStore,
    virtual_network: Mutex<VirtualNetworkManager>,
    traffic: Mutex<TrafficSampler>,
    default_mixed_port: u16,
    data_dir: PathBuf,
}

type SharedServices = Arc<AppServices>;

#[tauri::command]
fn project_runtime_config(
    profile_yaml: String,
    selected_address: Option<String>,
    routing_mode: String,
) -> Result<String, String> {
    let mode = RoutingMode::parse(&routing_mode).ok_or_else(|| "invalid routingMode".to_string())?;
    let mut options = ProjectOptions::default();
    options.routing_mode = mode;
    options.selected_address = selected_address;
    let profile = if mode == RoutingMode::Direct {
        None
    } else {
        Some(profile_yaml.as_str())
    };
    projection::project_runtime_yaml(profile, &options).map_err(|e| e.to_string())
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
) -> Result<CoreStatus, String> {
    let mode = RoutingMode::parse(&routing_mode).ok_or_else(|| "invalid routingMode".to_string())?;
    let mut options = ProjectOptions::default();
    options.routing_mode = mode;
    options.selected_address = selected_address;

    let bin = resolve_mihomo_binary(&app)?;
    let profile = if mode == RoutingMode::Direct {
        None
    } else {
        Some(profile_yaml.as_str())
    };
    let mut status = services.core.start(profile, &options, &bin)?;
    services.traffic.lock().reset();

    if enable_system_proxy.unwrap_or(false) {
        let endpoint = ProxyEndpoint {
            host: options.listen_address.clone(),
            port: options.mixed_port,
        };
        match services.system_proxy.enable(&endpoint) {
            Ok(proxy_status) => {
                status.message = format!("{}; {}", status.message, proxy_status.message);
            }
            Err(err) => {
                status.message =
                    format!("{}; system proxy not applied: {err}", status.message);
            }
        }
    }

    Ok(status)
}

#[tauri::command]
fn stop_core(services: State<'_, SharedServices>) -> Result<CoreStatus, String> {
    let status = services.core.stop()?;
    services.traffic.lock().reset();
    let proxy_note = match services.system_proxy.disable() {
        Ok(s) => s.message,
        Err(err) => format!("system proxy restore failed: {err}"),
    };
    Ok(CoreStatus {
        running: status.running,
        pid: status.pid,
        message: format!("{}; {proxy_note}", status.message),
        controller_port: status.controller_port,
    })
}

#[tauri::command]
fn system_proxy_status(services: State<'_, SharedServices>) -> SystemProxyStatus {
    services.system_proxy.status()
}

#[tauri::command]
fn set_system_proxy(
    services: State<'_, SharedServices>,
    enabled: bool,
    host: Option<String>,
    port: Option<u16>,
) -> Result<SystemProxyStatus, String> {
    if enabled {
        let endpoint = ProxyEndpoint {
            host: host.unwrap_or_else(|| "127.0.0.1".into()),
            port: port.unwrap_or(services.default_mixed_port),
        };
        services.system_proxy.enable(&endpoint)
    } else {
        services.system_proxy.disable()
    }
}

#[tauri::command]
async fn detect_exit_ip(endpoints: Option<Vec<String>>) -> Result<exit_ip::ExitIpResult, String> {
    exit_ip::detect_exit_ip(endpoints).await
}

#[tauri::command]
fn run_speed_test(
    app: AppHandle,
    services: State<'_, SharedServices>,
    request: SpeedTestRequest,
) -> Result<SpeedTestResponse, String> {
    let bin = resolve_bundled_binary(&app, "viasix-cfst").or_else(|_| {
        let sidecar = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("sidecar");
        speed_test::resolve_cfst_binary(&sidecar)
    })?;
    let work = services.data_dir.join("cfst");
    speed_test::run_speed_test(&bin, &work, &request)
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
async fn probe_controller(services: State<'_, SharedServices>) -> Result<ControllerHealth, String> {
    let Some((port, secret)) = services.core.controller_credentials() else {
        return Ok(ControllerHealth {
            ok: false,
            endpoint: String::new(),
            message: "Mihomo is not running".into(),
            version: None,
        });
    };
    Ok(controller::probe("127.0.0.1", port, &secret).await)
}

#[tauri::command]
async fn sample_traffic(services: State<'_, SharedServices>) -> Result<TrafficSnapshot, String> {
    let Some((port, secret)) = services.core.controller_credentials() else {
        services.traffic.lock().reset();
        return Ok(TrafficSnapshot {
            live: false,
            up_bps: 0,
            down_bps: 0,
            upload_total: 0,
            download_total: 0,
            message: "Mihomo is not running".into(),
        });
    };

    // Take sampler state, await without holding the mutex, then put it back.
    let mut sampler = {
        let mut guard = services.traffic.lock();
        std::mem::take(&mut *guard)
    };
    let snap = sampler.sample("127.0.0.1", port, &secret).await;
    *services.traffic.lock() = sampler;
    Ok(snap)
}

#[tauri::command]
fn virtual_network_capability() -> VirtualNetworkCapability {
    VirtualNetworkManager::capability()
}

#[tauri::command]
fn virtual_network_status(services: State<'_, SharedServices>) -> VirtualNetworkStatus {
    services.virtual_network.lock().status()
}

#[tauri::command]
fn set_virtual_network(
    services: State<'_, SharedServices>,
    enabled: bool,
) -> Result<VirtualNetworkStatus, String> {
    let mut mgr = services.virtual_network.lock();
    if enabled {
        mgr.enable()
    } else {
        mgr.disable()
    }
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let data = default_data_dir(app.handle());
            let work = data.join("runtime");
            let services = Arc::new(AppServices {
                core: Arc::new(CoreRuntime::new(work)),
                system_proxy: SystemProxyManager::new(data.clone()),
                prefs: PrefsStore::new(data.clone()),
                virtual_network: Mutex::new(VirtualNetworkManager::default()),
                traffic: Mutex::new(TrafficSampler::default()),
                default_mixed_port: ProjectOptions::default().mixed_port,
                data_dir: data,
            });
            app.manage(services);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            project_runtime_config,
            core_status,
            start_core,
            stop_core,
            system_proxy_status,
            set_system_proxy,
            detect_exit_ip,
            run_speed_test,
            load_session_prefs,
            save_session_prefs,
            app_version,
            probe_controller,
            sample_traffic,
            virtual_network_capability,
            virtual_network_status,
            set_virtual_network
        ])
        .run(tauri::generate_context!())
        .expect("error while running ViaSix Windows");
}
