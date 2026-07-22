//! Configuration connectivity checks through the local mixed proxy.

use serde::Serialize;
use std::time::Duration;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectivityResult {
    pub ok: bool,
    pub endpoint: String,
    pub via_proxy: String,
    pub exit_ip: Option<String>,
    pub family: Option<String>,
    pub latency_ms: u64,
    pub message: String,
}

/// Probe a public IP endpoint through the local mixed HTTP proxy.
pub async fn probe_via_proxy(
    proxy_host: &str,
    proxy_port: u16,
    url: Option<String>,
) -> Result<ConnectivityResult, String> {
    let target = url.unwrap_or_else(|| "https://api64.ipify.org?format=json".into());
    let proxy_url = format!("http://{proxy_host}:{proxy_port}");
    let started = std::time::Instant::now();

    let proxy = reqwest::Proxy::all(&proxy_url).map_err(|e| e.to_string())?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(12))
        .proxy(proxy)
        .user_agent("ViaSix-Windows/0.1")
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .get(&target)
        .send()
        .await
        .map_err(|e| format!("proxy request failed: {e}"))?;

    let latency_ms = started.elapsed().as_millis() as u64;
    if !response.status().is_success() {
        return Ok(ConnectivityResult {
            ok: false,
            endpoint: target,
            via_proxy: proxy_url,
            exit_ip: None,
            family: None,
            latency_ms,
            message: format!("HTTP {} via proxy", response.status()),
        });
    }

    let body = response.text().await.map_err(|e| e.to_string())?;
    let ip = parse_ip(&body);
    let family = ip.as_ref().map(|v| {
        if v.contains(':') {
            "ipv6".to_string()
        } else {
            "ipv4".to_string()
        }
    });

    Ok(ConnectivityResult {
        ok: ip.is_some(),
        endpoint: target,
        via_proxy: proxy_url,
        exit_ip: ip.clone(),
        family: family.clone(),
        latency_ms,
        message: match (&ip, &family) {
            (Some(ip), Some(family)) => {
                format!("代理连通 · 出口 {family} {ip} · {latency_ms} ms")
            }
            _ => format!("代理已响应但无法解析出口 IP · {latency_ms} ms"),
        },
    })
}

fn parse_ip(body: &str) -> Option<String> {
    let trimmed = body.trim();
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed) {
        if let Some(ip) = value.get("ip").and_then(|v| v.as_str()) {
            let ip = ip.trim();
            if !ip.is_empty() {
                return Some(ip.to_string());
            }
        }
    }
    if !trimmed.is_empty() && !trimmed.contains('<') && trimmed.len() < 128 {
        return Some(trimmed.to_string());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_json_ip() {
        assert_eq!(
            parse_ip(r#"{"ip":"2001:db8::1"}"#).as_deref(),
            Some("2001:db8::1")
        );
    }
}
