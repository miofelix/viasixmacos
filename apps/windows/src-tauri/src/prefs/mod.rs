//! Lightweight session preferences persisted under app data.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SessionPrefs {
    pub profile_yaml: String,
    pub selected_address: String,
    pub routing_mode: String,
    pub system_proxy_enabled: bool,
    pub last_speed_ip_range: String,
    pub disable_download: bool,
    #[serde(default)]
    pub speed_threads: Option<u32>,
    #[serde(default)]
    pub speed_ping_count: Option<u32>,
    #[serde(default)]
    pub speed_download_count: Option<u32>,
    #[serde(default)]
    pub speed_download_time: Option<u32>,
    #[serde(default)]
    pub speed_httping: Option<bool>,
    #[serde(default)]
    pub speed_port: Option<u16>,
    #[serde(default)]
    pub exit_ip_mode: Option<String>,
    #[serde(default)]
    pub last_section: Option<String>,
    #[serde(default)]
    pub mixed_port: Option<u16>,
    #[serde(default)]
    pub controller_port: Option<u16>,
    #[serde(default)]
    pub close_to_tray: Option<bool>,
    #[serde(default)]
    pub tun_stack: Option<String>,
    #[serde(default)]
    pub tun_mtu: Option<u16>,
    #[serde(default)]
    pub udp_enabled: Option<bool>,
    #[serde(default)]
    pub sniffing_enabled: Option<bool>,
    /// `custom` | `bundled` — speed-test IP source mode.
    #[serde(default)]
    pub ip_source_mode: Option<String>,
}

pub struct PrefsStore {
    path: PathBuf,
}

impl PrefsStore {
    pub fn new(data_dir: PathBuf) -> Self {
        Self {
            path: data_dir.join("session-prefs.json"),
        }
    }

    pub fn load(&self) -> SessionPrefs {
        match fs::read_to_string(&self.path) {
            Ok(raw) => serde_json::from_str(&raw).unwrap_or_default(),
            Err(_) => SessionPrefs::default(),
        }
    }

    pub fn save(&self, prefs: &SessionPrefs) -> Result<(), String> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let raw = serde_json::to_vec_pretty(prefs).map_err(|e| e.to_string())?;
        fs::write(&self.path, raw).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn round_trips_prefs() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-prefs-{stamp}"));
        let store = PrefsStore::new(dir.clone());
        let prefs = SessionPrefs {
            profile_yaml: "proxies: []\n".into(),
            selected_address: "2001:db8::1".into(),
            routing_mode: "rule".into(),
            system_proxy_enabled: true,
            last_speed_ip_range: "2606:4700::/32".into(),
            disable_download: true,
            speed_threads: Some(120),
            speed_ping_count: Some(6),
            speed_download_count: Some(8),
            speed_download_time: Some(5),
            speed_httping: Some(true),
            speed_port: Some(443),
            exit_ip_mode: Some("ipv6".into()),
            last_section: Some("nodes".into()),
            mixed_port: Some(11451),
            controller_port: Some(9090),
            close_to_tray: Some(true),
            tun_stack: Some("mixed".into()),
            tun_mtu: Some(1500),
            udp_enabled: Some(true),
            sniffing_enabled: Some(true),
            ip_source_mode: Some("custom".into()),
        };
        store.save(&prefs).unwrap();
        let loaded = store.load();
        assert_eq!(loaded.selected_address, "2001:db8::1");
        assert!(loaded.system_proxy_enabled);
        assert_eq!(loaded.speed_threads, Some(120));
        assert_eq!(loaded.exit_ip_mode.as_deref(), Some("ipv6"));
        assert_eq!(loaded.mixed_port, Some(11451));
        assert_eq!(loaded.close_to_tray, Some(true));
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn loads_legacy_prefs_without_new_fields() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-prefs-legacy-{stamp}"));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("session-prefs.json");
        fs::write(
            &path,
            r#"{"profileYaml":"x","selectedAddress":"::1","routingMode":"rule","systemProxyEnabled":false,"lastSpeedIpRange":"","disableDownload":true}"#,
        )
        .unwrap();
        let store = PrefsStore::new(dir.clone());
        let loaded = store.load();
        assert_eq!(loaded.selected_address, "::1");
        assert!(loaded.speed_threads.is_none());
        assert!(loaded.mixed_port.is_none());
        let _ = fs::remove_dir_all(dir);
    }
}
