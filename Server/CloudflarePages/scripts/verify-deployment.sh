#!/bin/zsh

set -euo pipefail

umask 077

fail() {
    print -u2 "Cloudflare Pages verification failed: $1"
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  verify-deployment.sh --host <pages-or-custom-domain> --uuid <UUID>
  verify-deployment.sh --host <pages-or-custom-domain> --uuid-file <path>

This checks HTTPS, the configuration page, and the Pages Clash endpoint.
It does not perform a complete VLESS data-plane test.
EOF
}

host=${VIASIX_PAGES_HOST:-}
uuid=${VIASIX_PAGES_UUID:-}
uuid_file=""

while (( $# > 0 )); do
    case "$1" in
        --host)
            (( $# >= 2 )) || fail "--host requires a value"
            host=$2
            shift 2
            ;;
        --uuid)
            (( $# >= 2 )) || fail "--uuid requires a value"
            uuid=$2
            shift 2
            ;;
        --uuid-file)
            (( $# >= 2 )) || fail "--uuid-file requires a path"
            uuid_file=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

if [[ -n "$uuid_file" ]]; then
    [[ -f "$uuid_file" && ! -L "$uuid_file" ]] \
        || fail "UUID file must be a regular, non-symlink file"
    uuid=$(/usr/bin/sed -n '1p' "$uuid_file")
fi

uuid=$(print -r -- "$uuid" | /usr/bin/tr '[:upper:]' '[:lower:]')
print -r -- "$uuid" \
    | /usr/bin/grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' \
    || fail "UUID must be a valid UUID v4"
print -r -- "$host" \
    | /usr/bin/grep -Eq '^[A-Za-z0-9.-]+$' \
    || fail "host must be a domain without scheme, port, or path"

temp_root=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || print -r -- "${TMPDIR:-/tmp}")
work_directory=$(mktemp -d "${temp_root%/}/com.felix.viasix.pages-verify.XXXXXX") \
    || fail "cannot create a private temporary directory"

cleanup() {
    if [[ -d "$work_directory" && ! -L "$work_directory" \
        && "$work_directory" == "${temp_root%/}/com.felix.viasix.pages-verify."* ]]; then
        /bin/rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT

curl_common=(
    --fail
    --silent
    --show-error
    --location
    --proto '=https'
    --proto-redir '=https'
    --tlsv1.2
    --connect-timeout 15
    --max-time 45
    --user-agent 'ViaSix-Pages-Deployment-Check/1.0'
)

config_url="https://${host}/${uuid}"
clash_url="https://${host}/${uuid}/pcl"
/usr/bin/curl "${curl_common[@]}" --output "$work_directory/config.html" "$config_url"
/usr/bin/curl "${curl_common[@]}" --output "$work_directory/clash.yaml" "$clash_url"

/usr/bin/grep -Fq "$uuid" "$work_directory/config.html" \
    || fail "configuration page does not contain the expected UUID"
if /usr/bin/grep -Fq 'vless://' "$work_directory/config.html" \
    || /usr/bin/grep -Fq 'VLESS:' "$work_directory/config.html"; then
    fail "configuration page must publish only the Mihomo YAML endpoint"
fi
if /usr/bin/grep -Fqi 'error code: 1101' "$work_directory/config.html"; then
    fail "Cloudflare returned error 1101"
fi
/usr/bin/grep -Eq '^[[:space:]]*type: (vless|\\u0076\\u006c\\u0065\\u0073\\u0073)[[:space:]]*$' \
    "$work_directory/clash.yaml" \
    || fail "Pages Clash endpoint does not contain a VLESS proxy"
/usr/bin/grep -Fq "uuid: $uuid" "$work_directory/clash.yaml" \
    || fail "Pages Clash endpoint UUID does not match"
/usr/bin/grep -Fq "servername: $host" "$work_directory/clash.yaml" \
    || fail "Pages Clash endpoint Server Name does not match"
/usr/bin/grep -Fq 'path: "/?ed=2560"' "$work_directory/clash.yaml" \
    || fail "Pages Clash endpoint WebSocket path does not match"
/usr/bin/grep -Fq 'tls: true' "$work_directory/clash.yaml" \
    || fail "Pages Clash endpoint is not configured for TLS"
/usr/bin/grep -Fq 'primary-server: selected-ip' "$work_directory/clash.yaml" \
    || fail "Pages endpoint does not request ViaSix selected-IP injection"
/usr/bin/grep -Fq 'udp: false' "$work_directory/clash.yaml" \
    || fail "Pages endpoint does not disable UDP on the proxy"
if /usr/bin/grep -Eq '^[[:space:]]+(routing-mode|udp-enabled|log-level|sniffing-enabled|bypass-private-networks):' \
    "$work_directory/clash.yaml"; then
    fail "Pages endpoint contains removed legacy x-viasix settings"
fi
if /usr/bin/grep -Eq '^[[:space:]]+server:[[:space:]]' "$work_directory/clash.yaml"; then
    fail "Pages endpoint must not publish a proxy server address"
fi

print "HTTPS configuration page verified: $config_url"
print "Pages Clash endpoint verified: $clash_url"
print "Deployment metadata is compatible with ViaSix selected-IP YAML import."
print -u2 "Note: run a ViaSix connection test to verify the complete VLESS data path."
