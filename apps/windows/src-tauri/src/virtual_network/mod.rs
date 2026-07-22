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

    pub fn preflight(&self) -> TunPreflight {
        evaluate_tun_preflight(
            self.enabled,
            find_wintun(&self.sidecar_dir).is_some(),
            cfg!(windows),
        )
    }
}

/// Preflight result for TUN/Wintun before (re)starting Mihomo.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TunPreflight {
    pub ready: bool,
    pub requested: bool,
    pub wintun_available: bool,
    pub on_windows: bool,
    pub issues: Vec<String>,
    pub message: String,
}

/// Pure evaluation of TUN readiness (unit-tested; used by commands and start path).
pub fn evaluate_tun_preflight(
    requested: bool,
    wintun_available: bool,
    on_windows: bool,
) -> TunPreflight {
    if !requested {
        return TunPreflight {
            ready: true,
            requested: false,
            wintun_available,
            on_windows,
            issues: Vec::new(),
            message: "未请求虚拟网卡（用户态本地代理）".into(),
        };
    }

    let mut issues = Vec::new();
    if !on_windows {
        issues.push("虚拟网卡 TUN 仅在 Windows 构建可用".into());
    }
    if !wintun_available {
        issues.push("缺少 wintun.dll — 请在 Windows 上执行 pnpm prebuild（fetch-wintun）".into());
    }

    let ready = issues.is_empty();
    let message = if ready {
        "虚拟网卡预检通过（Wintun 可用；启动 Mihomo 通常仍需管理员）".into()
    } else {
        format!("虚拟网卡预检未通过：{}", issues.join("；"))
    };

    TunPreflight {
        ready,
        requested: true,
        wintun_available,
        on_windows,
        issues,
        message,
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
    fn preflight_ok_when_not_requested() {
        let p = evaluate_tun_preflight(false, false, true);
        assert!(p.ready);
        assert!(p.issues.is_empty());
    }

    #[test]
    fn preflight_fails_without_wintun_when_requested() {
        let p = evaluate_tun_preflight(true, false, true);
        assert!(!p.ready);
        assert!(!p.issues.is_empty());
        assert!(p.message.contains("预检未通过"));
    }

    #[test]
    fn preflight_ok_when_requested_and_wintun_present_on_windows() {
        let p = evaluate_tun_preflight(true, true, true);
        assert!(p.ready);
        assert!(p.issues.is_empty());
    }

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

    /// Mirrors the fixed set_virtual_network pattern: enable/disable then
    /// preflight under the *same* guard (no second lock).
    #[test]
    fn enable_then_preflight_under_single_guard() {
        use parking_lot::Mutex;
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-vn-guard-{stamp}"));
        let _ = fs::create_dir_all(&dir);
        if cfg!(windows) {
            fs::write(dir.join("wintun.dll"), b"fake").unwrap();
        }
        let locked = Mutex::new(VirtualNetworkManager::new(dir.clone()));
        let (status, pre) = {
            let mut mgr = locked.lock();
            let status = if cfg!(windows) {
                mgr.enable().expect("enable with wintun")
            } else {
                mgr.disable().expect("disable always ok")
            };
            // Must not re-lock `locked` here — that would deadlock with parking_lot.
            let pre = mgr.preflight();
            (status, pre)
        };
        if cfg!(windows) {
            assert!(status.enabled);
            assert!(pre.requested);
            assert!(pre.ready, "{pre:?}");
        } else {
            assert!(!status.enabled);
            assert!(pre.ready);
            assert!(!pre.requested);
        }
        let _ = fs::remove_dir_all(dir);
    }
}
