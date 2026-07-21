#!/bin/zsh

set -euo pipefail

umask 077

readonly mihomo_version="1.19.29"

fail() {
    print -u2 "Mihomo preparation failed: $1"
    exit 1
}

if (( $# < 1 || $# > 2 )); then
    print -u2 "Usage: $0 <destination> [arm64|x86_64]"
    exit 64
fi

destination=$1
requested_architecture=${2:-$(uname -m)}
[[ "$destination" == /* ]] || fail "destination must be an absolute path"

case "$requested_architecture" in
    arm64)
        readonly archive_name="mihomo-darwin-arm64-v1.19.29.gz"
        readonly archive_url="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/$archive_name"
        readonly archive_sha256="4dc25df9e899f14161911302a8ee5fc9e202ed9c976fc405bf82c50ff27466ca"
        readonly payload_sha256="ec66e3e883bdc3fca06753784e324e08921e13239f8e945587cb1bfbf4c6b936"
        readonly payload_size="43229330"
        readonly mihomo_reported_architecture="arm64"
        ;;
    x86_64)
        readonly archive_name="mihomo-darwin-amd64-v1-v1.19.29.gz"
        readonly archive_url="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/$archive_name"
        readonly archive_sha256="addf68bf604e05cce5334e949bb8915dd68b25744669b320f7d4c1e240ab92a0"
        readonly payload_sha256="a139a209965e34ef30fac77ea9bfa9e6ab63c01cad6f94804131fd7f4a552c02"
        readonly payload_size="47015456"
        readonly mihomo_reported_architecture="amd64"
        ;;
    *)
        fail "unsupported architecture: $requested_architecture"
        ;;
esac

temp_root=$(getconf DARWIN_USER_TEMP_DIR) \
    || fail "cannot resolve the per-user temporary directory"
[[ -d "$temp_root" && ! -L "$temp_root" ]] \
    || fail "per-user temporary directory is missing or unsafe: $temp_root"

work_directory=$(mktemp -d "${temp_root%/}/com.felix.viasix.mihomo.XXXXXX") \
    || fail "cannot create a private temporary directory"
payload_path="$work_directory/mihomo"
destination_temporary_path=""
cache_temporary_path=""

cleanup() {
    if [[ -n "$cache_temporary_path" && -f "$cache_temporary_path" \
        && ! -L "$cache_temporary_path" ]]; then
        rm -f -- "$cache_temporary_path"
    fi
    if [[ -n "$destination_temporary_path" && -f "$destination_temporary_path" \
        && ! -L "$destination_temporary_path" ]]; then
        rm -f -- "$destination_temporary_path"
    fi
    if [[ -d "$work_directory" && ! -L "$work_directory" \
        && "$work_directory" == "${temp_root%/}/com.felix.viasix.mihomo."* ]]; then
        rm -rf -- "$work_directory"
    fi
}
trap cleanup EXIT

verify_sha256() {
    local file_path=$1
    local expected_sha256=$2
    local actual_sha256

    actual_sha256=$(/usr/bin/shasum -a 256 "$file_path" | /usr/bin/awk '{print $1}')
    [[ "$actual_sha256" == "$expected_sha256" ]]
}

source_path=${VIASIX_MIHOMO_SOURCE:-}
if [[ -n "$source_path" ]]; then
    [[ "$source_path" == /* ]] \
        || fail "VIASIX_MIHOMO_SOURCE must be an absolute path"
    [[ -f "$source_path" && ! -L "$source_path" ]] \
        || fail "VIASIX_MIHOMO_SOURCE must be a regular, non-symlink file"
    /bin/cp "$source_path" "$payload_path"
else
    cache_root=${VIASIX_MIHOMO_CACHE_DIR:-"$(getconf DARWIN_USER_CACHE_DIR)com.felix.viasix/BuildAssets/Mihomo"}
    [[ "$cache_root" == /* ]] || fail "Mihomo cache directory must be an absolute path"
    /bin/mkdir -p -m 700 "$cache_root/$mihomo_version/$requested_architecture"
    cache_directory="$cache_root/$mihomo_version/$requested_architecture"
    [[ -d "$cache_root" && ! -L "$cache_root" ]] \
        || fail "Mihomo cache root is missing or unsafe: $cache_root"
    [[ -d "$cache_root/$mihomo_version" && ! -L "$cache_root/$mihomo_version" ]] \
        || fail "Mihomo version cache is missing or unsafe"
    [[ -d "$cache_directory" && ! -L "$cache_directory" ]] \
        || fail "Mihomo cache directory is missing or unsafe: $cache_directory"
    [[ "$(/usr/bin/stat -f '%u' "$cache_root")" == "$(/usr/bin/id -u)" ]] \
        || fail "Mihomo cache root is not owned by the current user"
    [[ "$(/usr/bin/stat -f '%u' "$cache_directory")" == "$(/usr/bin/id -u)" ]] \
        || fail "Mihomo cache directory is not owned by the current user"
    /bin/chmod 700 "$cache_root" "$cache_root/$mihomo_version" "$cache_directory"

    cached_archive="$cache_directory/$archive_name"
    archive_path=""
    if [[ -e "$cached_archive" ]]; then
        [[ -f "$cached_archive" && ! -L "$cached_archive" ]] \
            || fail "cached Mihomo archive is not a regular file"
        [[ "$(/usr/bin/stat -f '%u' "$cached_archive")" == "$(/usr/bin/id -u)" ]] \
            || fail "cached Mihomo archive is not owned by the current user"
        /bin/chmod 600 "$cached_archive"
        if verify_sha256 "$cached_archive" "$archive_sha256"; then
            archive_path="$cached_archive"
        fi
    fi

    if [[ -z "$archive_path" ]]; then
        downloaded_archive="$work_directory/$archive_name"
        /usr/bin/curl \
            --fail \
            --location \
            --proto '=https' \
            --proto-redir '=https' \
            --tlsv1.2 \
            --retry 3 \
            --retry-all-errors \
            --connect-timeout 20 \
            --max-time 600 \
            --output "$downloaded_archive" \
            "$archive_url"
        verify_sha256 "$downloaded_archive" "$archive_sha256" \
            || fail "downloaded Mihomo archive SHA-256 mismatch"

        cache_temporary_path=$(mktemp "$cache_directory/.mihomo-archive.XXXXXX") \
            || fail "cannot create a private cache file"
        /bin/cp "$downloaded_archive" "$cache_temporary_path"
        /bin/chmod 600 "$cache_temporary_path"
        /bin/mv -f "$cache_temporary_path" "$cached_archive"
        cache_temporary_path=""
        archive_path="$cached_archive"
    fi

    verify_sha256 "$archive_path" "$archive_sha256" \
        || fail "cached Mihomo archive SHA-256 mismatch"
    /usr/bin/gzip -t "$archive_path" \
        || fail "Mihomo archive is not a valid gzip stream"
    /usr/bin/gzip -dc "$archive_path" > "$payload_path"
fi

[[ -f "$payload_path" && ! -L "$payload_path" ]] \
    || fail "Mihomo payload was not produced as a regular file"
[[ "$(/usr/bin/stat -f '%z' "$payload_path")" == "$payload_size" ]] \
    || fail "Mihomo payload size does not match the pinned release"
verify_sha256 "$payload_path" "$payload_sha256" \
    || fail "Mihomo payload SHA-256 mismatch"
/bin/chmod 755 "$payload_path"

/usr/bin/file "$payload_path" | /usr/bin/grep -q "Mach-O 64-bit executable" \
    || fail "Mihomo payload is not a 64-bit Mach-O executable"
actual_architectures=$(/usr/bin/lipo -archs "$payload_path") \
    || fail "cannot inspect Mihomo payload architecture"
[[ "$actual_architectures" == "$requested_architecture" ]] \
    || fail "Mihomo payload architecture is $actual_architectures, expected $requested_architecture"

version_output=$("$payload_path" -v 2>&1) \
    || fail "cannot execute Mihomo version probe"
version_line=${version_output%%$'\n'*}
expected_version_prefix="Mihomo Meta v${mihomo_version} darwin ${mihomo_reported_architecture} "
[[ "$version_line" == ${expected_version_prefix}* ]] \
    || fail "unexpected Mihomo version output: $version_line"

destination_directory=${destination:h}
[[ -d "$destination_directory" && ! -L "$destination_directory" ]] \
    || fail "destination directory is missing or unsafe: $destination_directory"
if [[ -e "$destination" && ( ! -f "$destination" || -L "$destination" ) ]]; then
    fail "destination exists and is not a regular file"
fi

destination_temporary_path=$(mktemp "$destination_directory/.mihomo-runtime.XXXXXX") \
    || fail "cannot create a private destination file"
/bin/cp "$payload_path" "$destination_temporary_path"
/bin/chmod 755 "$destination_temporary_path"
/bin/mv -f "$destination_temporary_path" "$destination"
destination_temporary_path=""

print "Prepared Mihomo v$mihomo_version ($requested_architecture) at $destination"
