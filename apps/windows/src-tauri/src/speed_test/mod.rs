//! CloudflareSpeedTest (CFST) runner for IPv6 node preference.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SpeedTestResult {
    pub ip: String,
    pub sent: String,
    pub received: String,
    pub loss: String,
    pub latency: String,
    pub speed: String,
    pub region: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeedTestRequest {
    /// Single IP or CIDR passed to CFST `-ip`.
    pub ip_range: Option<String>,
    /// Path to an IP list file for CFST `-f`. Ignored when `ip_range` is set.
    pub ip_file: Option<String>,
    pub threads: Option<u32>,
    pub ping_count: Option<u32>,
    pub download_count: Option<u32>,
    pub download_time: Option<u32>,
    /// When true, skip download speed (`-dd`).
    pub disable_download: Option<bool>,
    pub httping: Option<bool>,
    pub port: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeedTestResponse {
    pub results: Vec<SpeedTestResult>,
    pub message: String,
    pub result_csv_path: String,
}

pub fn run_speed_test(
    cfst_bin: &Path,
    work_dir: &Path,
    request: &SpeedTestRequest,
) -> Result<SpeedTestResponse, String> {
    if !cfst_bin.is_file() {
        return Err(format!(
            "CFST binary not found at {}. Run `pnpm prebuild`.",
            cfst_bin.display()
        ));
    }

    fs::create_dir_all(work_dir).map_err(io_err)?;
    let result_path = work_dir.join("result.csv");
    let _ = fs::remove_file(&result_path);

    let mut args = vec![
        "-o".into(),
        result_path.to_string_lossy().into_owned(),
        "-tp".into(),
        request.port.unwrap_or(443).to_string(),
        "-n".into(),
        request.threads.unwrap_or(200).to_string(),
        "-t".into(),
        request.ping_count.unwrap_or(4).to_string(),
        "-dn".into(),
        request.download_count.unwrap_or(10).to_string(),
        "-dt".into(),
        request.download_time.unwrap_or(10).to_string(),
        "-p".into(),
        "0".into(),
    ];

    let range = request
        .ip_range
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if let Some(range) = range {
        args.push("-ip".into());
        args.push(range.to_string());
    } else if let Some(file) = request
        .ip_file
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if !Path::new(file).is_file() {
            return Err(format!("IP file not found: {file}"));
        }
        args.push("-f".into());
        args.push(file.to_string());
    } else {
        return Err("Either ipRange or ipFile is required".into());
    }

    if request.httping.unwrap_or(true) {
        args.push("-httping".into());
    }
    if request.disable_download.unwrap_or(false) {
        args.push("-dd".into());
    }

    let mut command = Command::new(cfst_bin);
    command
        .args(&args)
        .current_dir(work_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let output = command
        .output()
        .map_err(|e| format!("failed to spawn CFST ({}): {e}", cfst_bin.display()))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(format!(
            "CFST exited with {}: {}{}",
            output.status,
            stderr.trim(),
            if stdout.trim().is_empty() {
                String::new()
            } else {
                format!(" / {}", stdout.trim())
            }
        ));
    }

    if !result_path.is_file() {
        return Err(format!(
            "CFST did not produce result file: {}",
            result_path.display()
        ));
    }

    let csv = fs::read_to_string(&result_path).map_err(io_err)?;
    let results = parse_result_csv(&csv);
    if results.is_empty() {
        return Err("No IP passed the speed test".into());
    }

    Ok(SpeedTestResponse {
        message: format!("Speed test finished: {} result(s)", results.len()),
        result_csv_path: result_path.to_string_lossy().into_owned(),
        results,
    })
}

pub fn parse_result_csv(csv: &str) -> Vec<SpeedTestResult> {
    let mut lines = csv.lines().filter(|l| !l.trim().is_empty());
    let _header = lines.next();
    lines
        .filter_map(|line| {
            let cols: Vec<&str> = line.split(',').map(str::trim).collect();
            if cols.len() < 6 || cols[0].is_empty() {
                return None;
            }
            Some(SpeedTestResult {
                ip: cols[0].to_string(),
                sent: cols[1].to_string(),
                received: cols[2].to_string(),
                loss: cols[3].to_string(),
                latency: cols[4].to_string(),
                speed: cols[5].to_string(),
                region: cols.get(6).unwrap_or(&"").to_string(),
            })
        })
        .collect()
}

pub fn resolve_cfst_binary(sidecar_dir: &Path) -> Result<PathBuf, String> {
    let name = if cfg!(windows) {
        "viasix-cfst.exe"
    } else {
        "viasix-cfst"
    };
    let plain = sidecar_dir.join(name);
    if plain.is_file() {
        return Ok(plain);
    }
    if let Ok(entries) = fs::read_dir(sidecar_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if file_name.starts_with("viasix-cfst") && path.is_file() {
                return Ok(path);
            }
        }
    }
    Err(format!(
        "CFST binary not found under {}. Run `pnpm prebuild`.",
        sidecar_dir.display()
    ))
}

fn io_err(err: io::Error) -> String {
    err.to_string()
}

/// Soft timeout helper for future async cancellation; currently unused by sync runner.
#[allow(dead_code)]
pub fn default_timeout() -> Duration {
    Duration::from_secs(600)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cfst_csv() {
        let csv = "\
IP,Sent,Received,Loss,Latency,Speed,Region
2001:db8::1,4,4,0.00,12.3,5.50,SJC
2001:db8::2,4,3,25.00,40.1,1.20,LAX
";
        let rows = parse_result_csv(csv);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].ip, "2001:db8::1");
        assert_eq!(rows[0].latency, "12.3");
        assert_eq!(rows[1].region, "LAX");
    }
}
