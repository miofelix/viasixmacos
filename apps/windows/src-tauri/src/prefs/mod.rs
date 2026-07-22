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
        };
        store.save(&prefs).unwrap();
        let loaded = store.load();
        assert_eq!(loaded.selected_address, "2001:db8::1");
        assert!(loaded.system_proxy_enabled);
        let _ = fs::remove_dir_all(dir);
    }
}
