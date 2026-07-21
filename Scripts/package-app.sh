#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
configuration=${1:-release}
dist_dir="$project_root/dist"
final_app_bundle="$dist_dir/ViaSix.app"

case "$configuration" in
    debug|release) ;;
    *)
        print -u2 "Unsupported configuration: $configuration (expected debug or release)"
        exit 1
        ;;
esac

build_arguments=(
    --package-path "$project_root"
    -c "$configuration"
    -Xswiftc -DVIASIX_PACKAGED_APP
    -Xlinker -dead_strip
)
swift build "${build_arguments[@]}"
binary_directory=$(swift build "${build_arguments[@]}" --show-bin-path)
binary_path="$binary_directory/ViaSix"
helper_binary_path="$binary_directory/ViaSixTunHelper"
runtime_relative_path="Contents/Library/HelperTools/com.felix.viasix.mihomo"
runtime_bundle_identifier="com.felix.viasix.mihomo"
runtime_version="1.19.29"

if [[ ! -x "$binary_path" ]]; then
    print -u2 "ViaSix executable was not produced at $binary_path"
    exit 1
fi
if [[ ! -x "$helper_binary_path" ]]; then
    print -u2 "ViaSix TUN helper was not produced at $helper_binary_path"
    exit 1
fi

application_architectures=$(/usr/bin/lipo -archs "$binary_path")
if [[ "$application_architectures" != "arm64" && "$application_architectures" != "x86_64" ]]; then
    print -u2 \
        "Packaged applications must contain exactly one supported architecture; found: $application_architectures"
    exit 1
fi

mkdir -p "$dist_dir"
package_workspace=$(mktemp -d "$dist_dir/.viasix-package.XXXXXX")
trap 'rm -rf "$package_workspace"' EXIT
app_bundle="$package_workspace/ViaSix.app"
contents_dir="$app_bundle/Contents"

mkdir -p \
    "$contents_dir/MacOS" \
    "$contents_dir/Library/HelperTools" \
    "$contents_dir/Library/LaunchDaemons" \
    "$contents_dir/Resources/Docs" \
    "$contents_dir/Resources/ThirdPartyLicenses"
cp "$binary_path" "$contents_dir/MacOS/ViaSix"
cp \
    "$helper_binary_path" \
    "$contents_dir/Library/HelperTools/com.felix.viasix.tun-helper"
"$project_root/Scripts/fetch-mihomo.sh" \
    "$app_bundle/$runtime_relative_path" \
    "$application_architectures"
cp \
    "$project_root/Packaging/LaunchDaemons/com.felix.viasix.tun-helper.plist" \
    "$contents_dir/Library/LaunchDaemons/com.felix.viasix.tun-helper.plist"
cp "$project_root/Packaging/Info.plist" "$contents_dir/Info.plist"
cp "$project_root/Docs/USER_GUIDE.md" "$contents_dir/Resources/Docs/USER_GUIDE.md"
cp "$project_root/CHANGELOG.md" "$contents_dir/Resources/CHANGELOG.md"
cp "$project_root/PRIVACY.md" "$contents_dir/Resources/PRIVACY.md"
cp "$project_root/SECURITY.md" "$contents_dir/Resources/SECURITY.md"
cp "$project_root/LICENSE" "$contents_dir/Resources/LICENSE"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"
cp \
    "$project_root/ThirdPartyLicenses/CloudflareSpeedTest-GPL-3.0.txt" \
    "$contents_dir/Resources/ThirdPartyLicenses/CloudflareSpeedTest-GPL-3.0.txt"
cp \
    "$project_root/ThirdPartyLicenses/mihomo-GPL-3.0.txt" \
    "$contents_dir/Resources/ThirdPartyLicenses/mihomo-GPL-3.0.txt"
cp \
    "$project_root/ThirdPartyLicenses/Yams-MIT.txt" \
    "$contents_dir/Resources/ThirdPartyLicenses/Yams-MIT.txt"
"$project_root/Scripts/generate-icon.sh" \
    "$project_root/Packaging/AppIcon.svg" \
    "$contents_dir/Resources/AppIcon.icns"

resource_bundle="$binary_directory/ViaSix_ViaSixCore.bundle"
if [[ ! -d "$resource_bundle" ]]; then
    print -u2 "ViaSixCore resource bundle was not produced at $resource_bundle"
    exit 1
fi

# The app resolves packaged defaults through Bundle.main before SwiftPM's
# development-only Bundle.module fallback. Copy only the current resource
# contract so an incremental SwiftPM bundle cannot reintroduce retired files.
for resource_name in ip.txt ipv6.txt local-proxy.json; do
    resource="$resource_bundle/$resource_name"
    if [[ ! -f "$resource" || -L "$resource" ]]; then
        print -u2 "ViaSixCore resource is missing or unsafe: $resource"
        exit 1
    fi
    ditto "$resource" "$contents_dir/Resources/$resource_name"
done

helper_path="$contents_dir/Library/HelperTools/com.felix.viasix.tun-helper"
mihomo_path="$app_bundle/$runtime_relative_path"
privileged_runtime_manifest="$contents_dir/Resources/PrivilegedRuntime.plist"
chmod 755 "$contents_dir/MacOS/ViaSix" "$helper_path" "$mihomo_path"
if [[ "$configuration" == "release" ]]; then
    /usr/bin/strip -S -x "$contents_dir/MacOS/ViaSix" "$helper_path"
fi
codesign_identity=${VIASIX_CODESIGN_IDENTITY:--}
if [[ "$codesign_identity" == "-" ]]; then
    codesign \
        --force \
        --identifier "$runtime_bundle_identifier" \
        --sign - \
        "$mihomo_path"
    codesign \
        --force \
        --identifier com.felix.viasix.tun-helper \
        --entitlements "$project_root/Packaging/Entitlements/ViaSixTunHelper.entitlements" \
        --sign - \
        "$helper_path"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --identifier "$runtime_bundle_identifier" \
        --sign "$codesign_identity" \
        "$mihomo_path"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --identifier com.felix.viasix.tun-helper \
        --entitlements "$project_root/Packaging/Entitlements/ViaSixTunHelper.entitlements" \
        --sign "$codesign_identity" \
        "$helper_path"
fi

mihomo_sha256=$(/usr/bin/shasum -a 256 "$mihomo_path" | /usr/bin/awk '{print $1}')
mihomo_signing_details=$(codesign -d --verbose=4 "$mihomo_path" 2>&1)
mihomo_cdhash=$(print -r -- "$mihomo_signing_details" | sed -n 's/^CDHash=//p' | head -n 1)
sha256_pattern='^[0-9a-f]{64}$'
cdhash_pattern='^[0-9a-f]{40}$'
if [[ ! "$mihomo_sha256" =~ $sha256_pattern || ! "$mihomo_cdhash" =~ $cdhash_pattern ]]; then
    print -u2 "Could not derive the signed Mihomo integrity identity"
    exit 1
fi

plutil -create xml1 "$privileged_runtime_manifest"
plutil -insert SchemaVersion -integer 1 "$privileged_runtime_manifest"
plutil -insert RuntimeVersion -string "$runtime_version" "$privileged_runtime_manifest"
plutil -insert Architecture -string "$application_architectures" "$privileged_runtime_manifest"
plutil -insert RelativePath -string "$runtime_relative_path" "$privileged_runtime_manifest"
plutil -insert BundleIdentifier -string "$runtime_bundle_identifier" "$privileged_runtime_manifest"
plutil -insert SHA256 -string "$mihomo_sha256" "$privileged_runtime_manifest"
plutil -insert CDHash -string "$mihomo_cdhash" "$privileged_runtime_manifest"
chmod 644 "$privileged_runtime_manifest"

if [[ "$codesign_identity" == "-" ]]; then
    codesign \
        --force \
        --entitlements "$project_root/Packaging/Entitlements/ViaSix.entitlements" \
        --sign - \
        "$app_bundle"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$project_root/Packaging/Entitlements/ViaSix.entitlements" \
        --sign "$codesign_identity" \
        "$app_bundle"
fi

if [[ "$configuration" == "debug" ]]; then
    VIASIX_ALLOW_LOCAL_PATHS=1 "$project_root/Scripts/verify-app.sh" "$app_bundle"
else
    "$project_root/Scripts/verify-app.sh" "$app_bundle"
fi

previous_app_bundle="$package_workspace/Previous-ViaSix.app"
if [[ -e "$final_app_bundle" ]]; then
    mv "$final_app_bundle" "$previous_app_bundle"
fi
if ! mv "$app_bundle" "$final_app_bundle"; then
    print -u2 "Failed to install packaged application at $final_app_bundle"
    if [[ -e "$previous_app_bundle" ]]; then
        mv "$previous_app_bundle" "$final_app_bundle" \
            || print -u2 "Failed to restore previous application bundle"
    fi
    exit 1
fi
rm -rf "$previous_app_bundle"

print "Created $final_app_bundle"
