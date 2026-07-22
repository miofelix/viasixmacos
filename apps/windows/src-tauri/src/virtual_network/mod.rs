//! Virtual network via Mihomo TUN + Wintun (Windows).
//!
//! Capability is available when `wintun.dll` is present next to the mihomo
//! binary (or in the sidecar directory). Enabling TUN still typically requires
//! running ViaSix elevated on Windows.

use serde::Serialize;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum VirtualNetworkBackend {
    /// Mihomo-managed TUN using Wintun on Windows.
    MihomoWintun,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VirtualNetworkStatus {
    pub available: bool,
    pub enabled: bool,
    pub backend: VirtualNetworkBackend,
    pub message: String,
    pub wintun_path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VirtualNetworkCapability {
    pub supported: bool,
    pub backend: VirtualNetworkBackend,
    pub requires_elevation: bool,
    pub message: String,
    pub wintun_path: Option<String>,
}

pub struct VirtualNetworkManager {
    enabled: bool,
    sidecar_dir: PathBuf,
}

impl VirtualNetworkManager {
    pub fn new(sidecar_dir: PathBuf) -> Self {
        Self {
            enabled: false,
            sidecar_dir,
        }
    }

    pub fn capability(&self) -> VirtualNetworkCapability {
        let wintun = find_wintun(&self.sidecar_dir);
        let supported = cfg!(windows) && wintun.is_some();
        VirtualNetworkCapability {
            supported,
            backend: VirtualNetworkBackend::MihomoWintun,
            requires_elevation: true,
            wintun_path: wintun.as_ref().map(|p| p.display().to_string()),
            message: if !cfg!(windows) {
                "Virtual network TUN is only available on Windows builds".into()
            } else if wintun.is_some() {
                "Wintun found; enable TUN then (re)start Mihomo. Admin rights usually required."
                    .into()
            } else {
                "wintun.dll missing — run `pnpm prebuild` (fetch-wintun) on Windows".into()
            },
        }
    }

    pub fn status(&self) -> VirtualNetworkStatus {
        let capability = self.capability();
        VirtualNetworkStatus {
            available: capability.supported,
            enabled: self.enabled,
            backend: capability.backend,
            wintun_path: capability.wintun_path.clone(),
            message: if self.enabled {
                "Virtual network preferred (Mihomo TUN/Wintun). Restart core to apply."
                    .into()
            } else {
                capability.message
            },
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    pub fn enable(&mut self) -> Result<VirtualNetworkStatus, String> {
        let capability = self.capability();
        if !capability.supported {
            return Err(capability.message);
        }
        self.enabled = true;
        Ok(self.status())
    }

    pub fn disable(&mut self) -> Result<VirtualNetworkStatus, String> {
        self.enabled = false;
        Ok(self.status())
    }
}

pub fn find_wintun(sidecar_dir: &Path) -> Option<PathBuf> {
    let candidates = [
        sidecar_dir.join("wintun.dll"),
        sidecar_dir.join("amd64").join("wintun.dll"),
        sidecar_dir.join("arm64").join("wintun.dll"),
    ];
    candidates.into_iter().find(|p| p.is_file())
}

/// Copy wintun.dll next to the mihomo binary so Mihomo can load it.
pub fn stage_wintun_beside_mihomo(mihomo_bin: &Path, sidecar_dir: &Path) -> Result<PathBuf, String> {
    let wintun =
        find_wintun(sidecar_dir).ok_or_else(|| "wintun.dll not found; run pnpm prebuild".to_string())?;
    let dest = mihomo_bin
        .parent()
        .ok_or_else(|| "mihomo path has no parent".to_string())?
        .join("wintun.dll");
    if dest != wintun {
        std::fs::copy(&wintun, &dest).map_err(|e| format!("copy wintun.dll: {e}"))?;
    }
    Ok(dest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn enable_requires_wintun_file() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-vn-{stamp}"));
        let _ = fs::create_dir_all(&dir);
        let mut mgr = VirtualNetworkManager::new(dir.clone());
        // On non-Windows CI hosts, supported is always false.
        if cfg!(windows) {
            assert!(mgr.enable().is_err());
            fs::write(dir.join("wintun.dll"), b"fake").unwrap();
            assert!(mgr.enable().is_ok());
            assert!(mgr.is_enabled());
            assert!(mgr.disable().is_ok());
        } else {
            assert!(mgr.enable().is_err());
            assert!(!mgr.capability().supported);
        }
        let _ = fs::remove_dir_all(dir);
    }
}
