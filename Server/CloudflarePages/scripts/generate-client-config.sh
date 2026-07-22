#!/bin/zsh

set -euo pipefail

umask 077

script_dir=${0:A:h}
resource_root=${script_dir:h}

fail() {
    print -u2 "ViaSix client configuration generation failed: $1"
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  generate-client-config.sh --host <pages-or-custom-domain> --uuid <UUID> [options]
  generate-client-config.sh --host <pages-or-custom-domain> --uuid-file <path> [options]

Options:
  --host <domain>        TLS SNI and WebSocket Host.
  --uuid <UUID>          The same UUID embedded in the Pages worker.
  --uuid-file <path>     Read the UUID from the first line of a local file.
  --port <port>          Cloudflare TLS port. Defaults to 443.
  --output-dir <path>    Private client output directory.
                         Defaults to ../dist/client.
  -h, --help             Show this help.
EOF
}

validate_uuid() {
    print -r -- "$1" \
        | /usr/bin/grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
}

host=${VIASIX_PAGES_HOST:-}
uuid=${VIASIX_PAGES_UUID:-}
uuid_file=""
port=443
output_dir="$resource_root/dist/client"

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
        --port)
            (( $# >= 2 )) || fail "--port requires a value"
            port=$2
            shift 2
            ;;
        --output-dir)
            (( $# >= 2 )) || fail "--output-dir requires a path"
            output_dir=$2
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
validate_uuid "$uuid" || fail "UUID must be a valid UUID v4"
print -r -- "$host" \
    | /usr/bin/grep -Eq '^[A-Za-z0-9.-]+$' \
    || fail "host must be a domain without scheme, port, or path"
[[ "$host" == *.* && "$host" != .* && "$host" != *. ]] \
    || fail "host must be a fully qualified domain"

print -r -- "$port" | /usr/bin/grep -Eq '^[0-9]+$' \
    || fail "port must be numeric"
(( port >= 1 && port <= 65535 )) || fail "port must be between 1 and 65535"

if [[ "$output_dir" != /* ]]; then
    output_dir="$resource_root/$output_dir"
fi
/bin/mkdir -p -m 700 "$output_dir"
[[ -d "$output_dir" && ! -L "$output_dir" ]] \
    || fail "output directory is missing or is a symlink"

yaml_path="$output_dir/viasix-mihomo.yaml"
obsolete_link_path="$output_dir/viasix-vless-link.txt"
if [[ -e "$yaml_path" && ( ! -f "$yaml_path" || -L "$yaml_path" ) ]]; then
    fail "output exists and is not a regular file: $yaml_path"
fi
if [[ -e "$obsolete_link_path" ]]; then
    [[ -f "$obsolete_link_path" && ! -L "$obsolete_link_path" ]] \
        || fail "obsolete share-link output is not a regular file: $obsolete_link_path"
    /bin/rm -f -- "$obsolete_link_path"
fi

yaml_temporary=$(mktemp "$output_dir/.mihomo-config.XXXXXX") \
    || fail "cannot create a temporary YAML file"

cleanup() {
    [[ -f "$yaml_temporary" && ! -L "$yaml_temporary" ]] \
        && /bin/rm -f -- "$yaml_temporary"
}
trap cleanup EXIT

cat > "$yaml_temporary" <<EOF
x-viasix:
  version: 1
  primary-server: selected-ip
proxies:
  - name: ViaSix Cloudflare Pages
    type: vless
    port: $port
    uuid: "$uuid"
    encryption: none
    udp: false
    tls: true
    servername: "$host"
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: "/?ed=2560"
      headers:
        Host: "$host"
EOF

/bin/chmod 600 "$yaml_temporary"
/bin/mv -f "$yaml_temporary" "$yaml_path"
yaml_temporary=""

print "Prepared ViaSix Mihomo YAML: $yaml_path"
print -u2 "The YAML intentionally omits server; apply a current IPv6 node in ViaSix before importing it."
