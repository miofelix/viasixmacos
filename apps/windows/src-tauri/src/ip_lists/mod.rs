//! Bundled IPv6 candidate lists (aligned with macOS Resources/ipv6.txt).

use std::fs;
use std::path::{Path, PathBuf};

/// Embedded copy of macOS `ViaSixCore/Resources/ipv6.txt`.
pub const BUNDLED_IPV6_TXT: &str = include_str!("../../resources/ipv6.txt");

pub fn ipv6_list_path(data_dir: &Path) -> PathBuf {
    data_dir.join("ipv6.txt")
}

/// Ensure `data_dir/ipv6.txt` exists (install bundled defaults when missing).
pub fn ensure_ipv6_list(data_dir: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(data_dir).map_err(|e| e.to_string())?;
    let path = ipv6_list_path(data_dir);
    if !path.is_file() {
        fs::write(&path, BUNDLED_IPV6_TXT.trim_end()).map_err(|e| e.to_string())?;
    }
    Ok(path)
}

/// Force-reset the managed list from the embedded bundle.
pub fn reset_ipv6_list(data_dir: &Path) -> Result<PathBuf, String> {
    fs::create_dir_all(data_dir).map_err(|e| e.to_string())?;
    let path = ipv6_list_path(data_dir);
    fs::write(&path, BUNDLED_IPV6_TXT.trim_end()).map_err(|e| e.to_string())?;
    Ok(path)
}

pub fn read_ipv6_list(data_dir: &Path) -> Result<String, String> {
    let path = ensure_ipv6_list(data_dir)?;
    fs::read_to_string(path).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn installs_and_reads_list() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("viasix-ipv6-{stamp}"));
        let path = ensure_ipv6_list(&dir).unwrap();
        assert!(path.is_file());
        let body = fs::read_to_string(&path).unwrap();
        assert!(body.contains("2606:4700::/32"));
        let _ = fs::remove_dir_all(dir);
    }
}
