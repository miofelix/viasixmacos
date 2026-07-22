//! Poll Mihomo `/connections` totals and derive instantaneous rates.

use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrafficSnapshot {
    pub live: bool,
    pub up_bps: u64,
    pub down_bps: u64,
    pub upload_total: u64,
    pub download_total: u64,
    pub message: String,
}

impl Default for TrafficSnapshot {
    fn default() -> Self {
        Self {
            live: false,
            up_bps: 0,
            down_bps: 0,
            upload_total: 0,
            download_total: 0,
            message: "no sample".into(),
        }
    }
}

#[derive(Debug, Default)]
pub struct TrafficSampler {
    last_upload: Option<u64>,
    last_download: Option<u64>,
    last_at: Option<Instant>,
    latest: TrafficSnapshot,
}

impl TrafficSampler {
    #[allow(dead_code)]
    pub fn latest(&self) -> TrafficSnapshot {
        self.latest.clone()
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }

    pub async fn sample(&mut self, host: &str, port: u16, secret: &str) -> TrafficSnapshot {
        match fetch_totals(host, port, secret).await {
            Ok((upload, download)) => {
                let now = Instant::now();
                let (up_bps, down_bps) = match (self.last_upload, self.last_download, self.last_at) {
                    (Some(prev_up), Some(prev_down), Some(prev_at)) => {
                        let secs = now.duration_since(prev_at).as_secs_f64().max(0.001);
                        let up = upload.saturating_sub(prev_up) as f64 / secs;
                        let down = download.saturating_sub(prev_down) as f64 / secs;
                        (up as u64, down as u64)
                    }
                    _ => (0, 0),
                };
                self.last_upload = Some(upload);
                self.last_download = Some(download);
                self.last_at = Some(now);
                self.latest = TrafficSnapshot {
                    live: true,
                    up_bps,
                    down_bps,
                    upload_total: upload,
                    download_total: download,
                    message: format!(
                        "↑ {}/s  ↓ {}/s  ·  Σ ↑ {}  ↓ {}",
                        format_rate(up_bps),
                        format_rate(down_bps),
                        format_bytes(upload),
                        format_bytes(download),
                    ),
                };
                self.latest.clone()
            }
            Err(err) => {
                self.latest = TrafficSnapshot {
                    live: false,
                    up_bps: 0,
                    down_bps: 0,
                    upload_total: self.last_upload.unwrap_or(0),
                    download_total: self.last_download.unwrap_or(0),
                    message: format!("traffic unavailable: {err}"),
                };
                self.latest.clone()
            }
        }
    }
}

#[derive(Debug, Deserialize)]
struct ConnectionsResponse {
    #[serde(rename = "uploadTotal", default)]
    upload_total: u64,
    #[serde(rename = "downloadTotal", default)]
    download_total: u64,
}

async fn fetch_totals(host: &str, port: u16, secret: &str) -> Result<(u64, u64), String> {
    let url = format!("http://{host}:{port}/connections");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(3))
        .build()
        .map_err(|e| e.to_string())?;
    let mut req = client.get(&url);
    if !secret.is_empty() {
        req = req.header("Authorization", format!("Bearer {secret}"));
    }
    let response = req.send().await.map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let body = response
        .json::<ConnectionsResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok((body.upload_total, body.download_total))
}

pub fn format_rate(bps: u64) -> String {
    format_bytes(bps)
}

pub fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} {}", UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_bytes() {
        assert_eq!(format_bytes(500), "500 B");
        assert_eq!(format_bytes(2048), "2.0 KB");
    }
}
