//! Persist profile.yaml under app data (macOS Application Support analogue).

use std::fs;
use std::path::{Path, PathBuf};

pub fn profile_path(data_dir: &Path) -> PathBuf {
    data_dir.join("profile.yaml")
}

pub fn load_profile(data_dir: &Path) -> Result<Option<String>, String> {
    let path = profile_path(data_dir);
    if !path.is_file() {
        return Ok(None);
    }
    let raw = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    if raw.trim().is_empty() {
        return Ok(None);
    }
    Ok(Some(raw))
}

pub fn save_profile(data_dir: &Path, yaml: &str) -> Result<String, String> {
    fs::create_dir_all(data_dir).map_err(|e| e.to_string())?;
    let path = profile_path(data_dir);
    if yaml.len() > 2 * 1024 * 1024 {
        return Err("profile too large (max 2 MiB)".into());
    }
    fs::write(&path, yaml).map_err(|e| e.to_string())?;
    Ok(path.display().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn round_trips_profile() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-profile-{stamp}"));
        let path = save_profile(&dir, "proxies: []\n").unwrap();
        assert!(PathBuf::from(&path).is_file());
        let loaded = load_profile(&dir).unwrap().unwrap();
        assert!(loaded.contains("proxies"));
        let _ = fs::remove_dir_all(dir);
    }
}
