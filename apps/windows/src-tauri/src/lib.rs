mod projection;
mod runtime;

use projection::{ProjectOptions, RoutingMode};
use runtime::{CoreStatus, CoreRuntime, SharedCore};
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Manager, State};

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
fn core_status(core: State<'_, SharedCore>) -> CoreStatus {
    core.status()
}

#[tauri::command]
fn start_core(
    app: AppHandle,
    core: State<'_, SharedCore>,
    profile_yaml: String,
    selected_address: Option<String>,
    routing_mode: String,
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
    core.start(profile, &options, &bin)
}

#[tauri::command]
fn stop_core(core: State<'_, SharedCore>) -> Result<CoreStatus, String> {
    core.stop()
}

fn resolve_mihomo_binary(app: &AppHandle) -> Result<PathBuf, String> {
    // Prefer Tauri externalBin sidecar path, then dev-relative sidecar/.
    if let Ok(sidecar) = app
        .path()
        .resolve("viasix-mihomo", tauri::path::BaseDirectory::Resource)
    {
        let candidate = if cfg!(windows) {
            sidecar.with_extension("exe")
        } else {
            sidecar
        };
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    let mut dev = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    dev.push("sidecar");
    let name = if cfg!(windows) {
        "viasix-mihomo.exe"
    } else {
        "viasix-mihomo"
    };
    // Tauri externalBin renames with target triple; also accept plain name for local dev.
    let plain = dev.join(name);
    if plain.is_file() {
        return Ok(plain);
    }

    if let Ok(entries) = std::fs::read_dir(&dev) {
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if file_name.starts_with("viasix-mihomo") && path.is_file() {
                return Ok(path);
            }
        }
    }

    Err(format!(
        "Mihomo binary not found under {}. Run `pnpm prebuild`.",
        dev.display()
    ))
}

fn default_work_dir(app: &AppHandle) -> PathBuf {
    app.path()
        .app_data_dir()
        .unwrap_or_else(|_| std::env::temp_dir().join("viasix-windows"))
        .join("runtime")
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let work = default_work_dir(app.handle());
            let core: SharedCore = Arc::new(CoreRuntime::new(work));
            app.manage(core);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            project_runtime_config,
            core_status,
            start_core,
            stop_core
        ])
        .run(tauri::generate_context!())
        .expect("error while running ViaSix Windows");
}
