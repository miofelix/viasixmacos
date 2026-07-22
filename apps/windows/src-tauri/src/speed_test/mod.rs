//! CloudflareSpeedTest (CFST) runner for IPv6 node preference.
//! Supports cancellable runs and single-node configuration tests.

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
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
    pub cancelled: bool,
}

#[derive(Debug, Default)]
pub struct SpeedTestSession {
    child: Mutex<Option<Child>>,
    cancel_requested: AtomicBool,
    running: AtomicBool,
}

impl SpeedTestSession {
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }

    pub fn request_cancel(&self) -> bool {
        if !self.running.load(Ordering::SeqCst) {
            return false;
        }
        self.cancel_requested.store(true, Ordering::SeqCst);
        if let Some(child) = self.child.lock().as_mut() {
            let _ = child.kill();
        }
        true
    }

    pub fn run(
        &self,
        cfst_bin: &Path,
        work_dir: &Path,
        request: &SpeedTestRequest,
    ) -> Result<SpeedTestResponse, String> {
        if self
            .running
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            return Err("Speed test already running".into());
        }
        self.cancel_requested.store(false, Ordering::SeqCst);
        let result = self.run_inner(cfst_bin, work_dir, request);
        *self.child.lock() = None;
        self.running.store(false, Ordering::SeqCst);
        self.cancel_requested.store(false, Ordering::SeqCst);
        result
    }

    fn run_inner(
        &self,
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

        let child = command
            .spawn()
            .map_err(|e| format!("failed to spawn CFST ({}): {e}", cfst_bin.display()))?;
        *self.child.lock() = Some(child);

        // Poll until exit or cancel.
        loop {
            if self.cancel_requested.load(Ordering::SeqCst) {
                if let Some(child) = self.child.lock().as_mut() {
                    let _ = child.kill();
                    let _ = child.wait();
                }
                return Ok(SpeedTestResponse {
                    results: Vec::new(),
                    message: "Speed test cancelled".into(),
                    result_csv_path: result_path.to_string_lossy().into_owned(),
                    cancelled: true,
                });
            }

            let status = {
                let mut guard = self.child.lock();
                match guard.as_mut() {
                    Some(child) => child.try_wait().map_err(|e| e.to_string())?,
                    None => break,
                }
            };

            if let Some(status) = status {
                // Drain process fully.
                let mut guard = self.child.lock();
                if let Some(mut child) = guard.take() {
                    let _ = child.wait();
                    if !status.success() && !self.cancel_requested.load(Ordering::SeqCst) {
                        return Err(format!("CFST exited with {status}"));
                    }
                }
                break;
            }

            std::thread::sleep(Duration::from_millis(120));
        }

        if self.cancel_requested.load(Ordering::SeqCst) {
            return Ok(SpeedTestResponse {
                results: Vec::new(),
                message: "Speed test cancelled".into(),
                result_csv_path: result_path.to_string_lossy().into_owned(),
                cancelled: true,
            });
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
            cancelled: false,
        })
    }
}

/// Built-in Cloudflare-style IPv6 CIDR presets (subset of macOS ipv6.txt).
pub fn ipv6_presets() -> Vec<IpPreset> {
    vec![
        IpPreset {
            id: "cf-main".into(),
            title: "Cloudflare 主段".into(),
            description: "2606:4700::/32".into(),
            ip_range: "2606:4700::/32".into(),
        },
        IpPreset {
            id: "cf-bundle".into(),
            title: "Cloudflare 常用 IPv6 段".into(),
            description: "macOS 默认 ipv6 列表核心段".into(),
            ip_range: [
                "2400:cb00::/32",
                "2606:4700::/32",
                "2803:f800::/32",
                "2405:b500::/32",
                "2405:8100::/32",
                "2a06:98c0::/29",
                "2c0f:f248::/32",
            ]
            .join(","),
        },
        IpPreset {
            id: "cf-apac".into(),
            title: "亚太相关段".into(),
            description: "2400:cb00 + 2405 段".into(),
            ip_range: "2400:cb00::/32,2405:b500::/32,2405:8100::/32".into(),
        },
    ]
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IpPreset {
    pub id: String,
    pub title: String,
    pub description: String,
    pub ip_range: String,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cfst_csv() {
        let csv = "IP,Sent,Received,Loss,Latency,Speed,Region\n\
2001:db8::1,4,4,0.00,12.3,0,TEST\n";
        let rows = parse_result_csv(csv);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].ip, "2001:db8::1");
        assert_eq!(rows[0].latency, "12.3");
    }

    #[test]
    fn presets_non_empty() {
        assert!(!ipv6_presets().is_empty());
    }
}
