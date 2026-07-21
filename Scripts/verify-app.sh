#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
app_bundle=${1:-"$project_root/dist/ViaSix.app"}
contents_dir="$app_bundle/Contents"
info_plist="$contents_dir/Info.plist"

fail() {
    print -u2 "App verification failed: $1"
    exit 1
}

[[ -d "$app_bundle" ]] || fail "bundle not found at $app_bundle"
[[ ! -L "$app_bundle" ]] || fail "application bundle must not be a symbolic link"
for required_directory in \
    "$contents_dir" \
    "$contents_dir/Library" \
    "$contents_dir/Library/HelperTools" \
    "$contents_dir/Resources"
do
    [[ -d "$required_directory" && ! -L "$required_directory" ]] \
        || fail "required bundle directory is missing or unsafe: $required_directory"
done
[[ -f "$info_plist" && ! -L "$info_plist" ]] || fail "missing or unsafe Contents/Info.plist"
plutil -lint "$info_plist" >/dev/null

executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$info_plist")
bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist")
development_region=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDevelopmentRegion" "$info_plist")
package_type=$(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$info_plist")
minimum_system=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$info_plist")
short_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist")
build_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
executable_path="$contents_dir/MacOS/$executable_name"
helper_path="$contents_dir/Library/HelperTools/com.felix.viasix.tun-helper"
installer_path="$contents_dir/Library/HelperTools/com.felix.viasix.tun-installer"
daemon_plist="$contents_dir/Library/LaunchDaemons/com.felix.viasix.tun-helper.plist"
mihomo_relative_path="Contents/Library/HelperTools/com.felix.viasix.mihomo"
mihomo_path="$app_bundle/$mihomo_relative_path"
privileged_runtime_manifest="$contents_dir/Resources/PrivilegedRuntime.plist"
short_version_pattern='^[0-9]+[.][0-9]+[.][0-9]+$'
build_version_pattern='^[0-9]+([.][0-9]+){0,2}$'
sha256_pattern='^[0-9a-f]{64}$'
cdhash_pattern='^[0-9a-f]{40}$'

[[ "$bundle_identifier" == "com.felix.viasix" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$development_region" == "zh-Hans" ]] || fail "unexpected development region: $development_region"
[[ "$package_type" == "APPL" ]] || fail "unexpected package type: $package_type"
[[ "$minimum_system" == "14.0" ]] || fail "unexpected minimum macOS version: $minimum_system"
[[ "$short_version" =~ $short_version_pattern ]] || fail "invalid application version: $short_version"
[[ "$build_version" =~ $build_version_pattern ]] || fail "invalid build version: $build_version"
[[ -x "$executable_path" ]] || fail "main executable is missing or not executable"
[[ ! -L "$executable_path" ]] || fail "main executable must not be a symbolic link"
file "$executable_path" | grep -q "Mach-O" || fail "main executable is not Mach-O"
[[ -x "$helper_path" ]] || fail "TUN helper is missing or not executable"
[[ ! -L "$helper_path" ]] || fail "TUN helper must not be a symbolic link"
file "$helper_path" | grep -q "Mach-O" || fail "TUN helper is not Mach-O"
[[ -x "$installer_path" ]] || fail "TUN installer is missing or not executable"
[[ ! -L "$installer_path" ]] || fail "TUN installer must not be a symbolic link"
file "$installer_path" | grep -q "Mach-O" || fail "TUN installer is not Mach-O"
[[ -x "$mihomo_path" ]] || fail "privileged Mihomo runtime is missing or not executable"
[[ ! -L "$mihomo_path" ]] || fail "privileged Mihomo runtime must not be a symbolic link"
file "$mihomo_path" | grep -q "Mach-O 64-bit executable" \
    || fail "privileged Mihomo runtime is not a 64-bit Mach-O executable"
[[ -f "$privileged_runtime_manifest" ]] || fail "privileged runtime manifest is missing"
[[ ! -L "$privileged_runtime_manifest" ]] \
    || fail "privileged runtime manifest must not be a symbolic link"
[[ "$(stat -f '%z' "$privileged_runtime_manifest")" -le 65536 ]] \
    || fail "privileged runtime manifest exceeds 65536 bytes"
plutil -lint "$privileged_runtime_manifest" >/dev/null
[[ -f "$daemon_plist" ]] || fail "LaunchDaemon plist is missing"
[[ ! -L "$daemon_plist" ]] || fail "LaunchDaemon plist must not be a symbolic link"
plutil -lint "$daemon_plist" >/dev/null

daemon_label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$daemon_plist")
daemon_program=$(/usr/libexec/PlistBuddy -c "Print :BundleProgram" "$daemon_plist")
daemon_user=$(/usr/libexec/PlistBuddy -c "Print :UserName" "$daemon_plist")
daemon_mach_service=$(
    /usr/libexec/PlistBuddy \
        -c "Print :MachServices:com.felix.viasix.tun-helper" \
        "$daemon_plist"
)
[[ "$daemon_label" == "com.felix.viasix.tun-helper" ]] \
    || fail "unexpected LaunchDaemon label: $daemon_label"
[[ "$daemon_program" == "Contents/Library/HelperTools/com.felix.viasix.tun-helper" ]] \
    || fail "unexpected LaunchDaemon BundleProgram: $daemon_program"
[[ "$daemon_user" == "root" ]] || fail "unexpected LaunchDaemon user: $daemon_user"
[[ "$daemon_mach_service" == "true" ]] \
    || fail "TUN helper Mach service is not enabled"
if /usr/libexec/PlistBuddy -c "Print :Program" "$daemon_plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Print :ProgramArguments" "$daemon_plist" >/dev/null 2>&1; then
    fail "LaunchDaemon must use only the fixed BundleProgram"
fi

if [[ -n "${VIASIX_EXPECTED_VERSION:-}" && "$short_version" != "$VIASIX_EXPECTED_VERSION" ]]; then
    fail "expected application version $VIASIX_EXPECTED_VERSION, found $short_version"
fi

if [[ -n "${VIASIX_EXPECTED_BUILD_VERSION:-}" && "$build_version" != "$VIASIX_EXPECTED_BUILD_VERSION" ]]; then
    fail "expected build version $VIASIX_EXPECTED_BUILD_VERSION, found $build_version"
fi

[[ "$(plutil -type SchemaVersion "$privileged_runtime_manifest")" == "integer" ]] \
    || fail "privileged runtime SchemaVersion must be an integer"
[[ "$(plutil -type RuntimeVersion "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime RuntimeVersion must be a string"
[[ "$(plutil -type Architecture "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime Architecture must be a string"
[[ "$(plutil -type RelativePath "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime RelativePath must be a string"
[[ "$(plutil -type BundleIdentifier "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime BundleIdentifier must be a string"
[[ "$(plutil -type SHA256 "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime SHA256 must be a string"
[[ "$(plutil -type CDHash "$privileged_runtime_manifest")" == "string" ]] \
    || fail "privileged runtime CDHash must be a string"

runtime_schema=$(plutil -extract SchemaVersion raw "$privileged_runtime_manifest")
runtime_version=$(plutil -extract RuntimeVersion raw "$privileged_runtime_manifest")
runtime_architecture=$(plutil -extract Architecture raw "$privileged_runtime_manifest")
runtime_relative_path=$(plutil -extract RelativePath raw "$privileged_runtime_manifest")
runtime_bundle_identifier=$(plutil -extract BundleIdentifier raw "$privileged_runtime_manifest")
runtime_sha256=$(plutil -extract SHA256 raw "$privileged_runtime_manifest")
runtime_cdhash=$(plutil -extract CDHash raw "$privileged_runtime_manifest")
[[ "$runtime_schema" == "1" ]] || fail "unsupported privileged runtime manifest schema: $runtime_schema"
[[ "$runtime_version" == "1.19.29" ]] \
    || fail "unexpected privileged Mihomo version: $runtime_version"
[[ "$runtime_architecture" == "arm64" || "$runtime_architecture" == "x86_64" ]] \
    || fail "unsupported privileged Mihomo architecture: $runtime_architecture"
[[ "$runtime_relative_path" == "$mihomo_relative_path" ]] \
    || fail "unexpected privileged Mihomo relative path: $runtime_relative_path"
[[ "$runtime_bundle_identifier" == "com.felix.viasix.mihomo" ]] \
    || fail "unexpected privileged Mihomo bundle identifier: $runtime_bundle_identifier"
[[ "$runtime_sha256" =~ $sha256_pattern ]] \
    || fail "privileged Mihomo SHA-256 is malformed"
[[ "$runtime_cdhash" =~ $cdhash_pattern ]] \
    || fail "privileged Mihomo CDHash is malformed"

for resource_name in ip.txt ipv6.txt local-proxy.json; do
    [[ -f "$contents_dir/Resources/$resource_name" ]] || fail "missing bundled resource: $resource_name"
done
plutil -convert xml1 -o /dev/null "$contents_dir/Resources/local-proxy.json"
listen_address=$(plutil -extract listenAddress raw "$contents_dir/Resources/local-proxy.json")
network_access_mode=$(plutil -extract networkAccessMode raw "$contents_dir/Resources/local-proxy.json")
[[ "$listen_address" == "127.0.0.1" ]] \
    || fail "bundled local proxy must listen on the IPv4 loopback address"
[[ "$network_access_mode" == "localProxy" ]] \
    || fail "bundled local proxy must default to local-only access"

for removed_resource in \
    server.json \
    template.json \
    xray \
    geoip.dat \
    geosite.dat \
    Xray-core-MPL-2.0.txt; do
    if [[ -e "$contents_dir/Resources/$removed_resource" ]] \
        || [[ -e "$contents_dir/Resources/ThirdPartyLicenses/$removed_resource" ]]; then
        fail "removed Xray-era resource is still bundled: $removed_resource"
    fi
done

[[ -f "$contents_dir/Resources/Docs/USER_GUIDE.md" ]] || fail "missing user guide"
[[ -f "$contents_dir/Resources/AppIcon.icns" ]] || fail "missing application icon"
for document_name in CHANGELOG.md LICENSE PRIVACY.md SECURITY.md THIRD_PARTY_NOTICES.md; do
    [[ -f "$contents_dir/Resources/$document_name" ]] \
        || fail "missing bundled document: $document_name"
done
cmp -s "$project_root/LICENSE" "$contents_dir/Resources/LICENSE" \
    || fail "bundled LICENSE does not match the repository copy"

for license_specification in \
    "CloudflareSpeedTest-GPL-3.0.txt 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986" \
    "mihomo-GPL-3.0.txt 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986" \
    "Yams-MIT.txt 0354b0ea403d2e78059c5ae0510a2cfae9f8eb306fcef094ac9fff5b47e20bed"
do
    license_name=${license_specification%% *}
    expected_digest=${license_specification#* }
    license_path="$contents_dir/Resources/ThirdPartyLicenses/$license_name"
    [[ -f "$license_path" ]] || fail "missing third-party license: $license_name"
    actual_digest=$(shasum -a 256 "$license_path" | awk '{print $1}')
    [[ "$actual_digest" == "$expected_digest" ]] \
        || fail "third-party license checksum mismatch: $license_name"
done

"$project_root/Scripts/check-doc-links.sh" "$contents_dir/Resources" >/dev/null

for forbidden_text in \
    "ipv6""-plan" \
    "ipv6""plan"; do
    if LC_ALL=C grep -R -a -F -q -- "$forbidden_text" "$contents_dir"; then
        fail "forbidden inherited content found in application bundle: $forbidden_text"
    fi
done

if [[ "${VIASIX_ALLOW_LOCAL_PATHS:-0}" != "1" ]] \
    && LC_ALL=C grep -R -a -F -q -- "$project_root" "$contents_dir"; then
    fail "local checkout path leaked into application bundle"
fi

codesign --verify --strict --verbose=2 "$mihomo_path"
codesign --verify --strict --verbose=2 "$helper_path"
codesign --verify --strict --verbose=2 "$installer_path"
codesign --verify --strict --verbose=2 "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

mihomo_signing_details=$(codesign -d --verbose=4 "$mihomo_path" 2>&1)
helper_signing_details=$(codesign -d --verbose=4 "$helper_path" 2>&1)
installer_signing_details=$(codesign -d --verbose=4 "$installer_path" 2>&1)
app_signing_details=$(codesign -d --verbose=4 "$app_bundle" 2>&1)
mihomo_identifier=$(print -r -- "$mihomo_signing_details" | sed -n 's/^Identifier=//p')
helper_identifier=$(print -r -- "$helper_signing_details" | sed -n 's/^Identifier=//p')
installer_identifier=$(print -r -- "$installer_signing_details" | sed -n 's/^Identifier=//p')
app_signing_identifier=$(print -r -- "$app_signing_details" | sed -n 's/^Identifier=//p')
mihomo_team_identifier=$(print -r -- "$mihomo_signing_details" | sed -n 's/^TeamIdentifier=//p')
helper_team_identifier=$(print -r -- "$helper_signing_details" | sed -n 's/^TeamIdentifier=//p')
installer_team_identifier=$(print -r -- "$installer_signing_details" | sed -n 's/^TeamIdentifier=//p')
app_team_identifier=$(print -r -- "$app_signing_details" | sed -n 's/^TeamIdentifier=//p')
actual_mihomo_cdhash=$(print -r -- "$mihomo_signing_details" | sed -n 's/^CDHash=//p' | head -n 1)
[[ "$app_signing_identifier" == "com.felix.viasix" ]] \
    || fail "unexpected application signing identifier: $app_signing_identifier"
[[ "$helper_identifier" == "com.felix.viasix.tun-helper" ]] \
    || fail "unexpected TUN helper signing identifier: $helper_identifier"
[[ "$installer_identifier" == "com.felix.viasix.tun-installer" ]] \
    || fail "unexpected TUN installer signing identifier: $installer_identifier"
[[ "$mihomo_identifier" == "$runtime_bundle_identifier" ]] \
    || fail "unexpected privileged Mihomo signing identifier: $mihomo_identifier"
[[ "$helper_team_identifier" == "$app_team_identifier" ]] \
    || fail "application/helper Team Identifier mismatch"
[[ "$installer_team_identifier" == "$app_team_identifier" ]] \
    || fail "application/installer Team Identifier mismatch"
[[ "$mihomo_team_identifier" == "$app_team_identifier" ]] \
    || fail "application/Mihomo Team Identifier mismatch"
if [[ -n "${VIASIX_EXPECTED_TEAM_IDENTIFIER:-}" \
    && "$app_team_identifier" != "$VIASIX_EXPECTED_TEAM_IDENTIFIER" ]]; then
    fail "expected Team Identifier $VIASIX_EXPECTED_TEAM_IDENTIFIER, found $app_team_identifier"
fi

if [[ "$app_team_identifier" != "not set" ]]; then
    for signing_specification in \
        "Mihomo|$mihomo_signing_details" \
        "TUN helper|$helper_signing_details" \
        "TUN installer|$installer_signing_details" \
        "application|$app_signing_details"
    do
        signing_name=${signing_specification%%|*}
        signing_details=${signing_specification#*|}
        print -r -- "$signing_details" | grep -Eq '^CodeDirectory .*flags=.*runtime' \
            || fail "$signing_name signature does not enable Hardened Runtime"
        print -r -- "$signing_details" | grep -q '^Timestamp=' \
            || fail "$signing_name signature has no trusted timestamp"
    done
fi

architectures=$(lipo -archs "$executable_path")
helper_architectures=$(lipo -archs "$helper_path")
installer_architectures=$(lipo -archs "$installer_path")
mihomo_architectures=$(lipo -archs "$mihomo_path")
[[ "$helper_architectures" == "$architectures" ]] \
    || fail "main/helper architecture mismatch: $architectures vs $helper_architectures"
[[ "$installer_architectures" == "$architectures" ]] \
    || fail "main/installer architecture mismatch: $architectures vs $installer_architectures"
[[ "$mihomo_architectures" == "$architectures" ]] \
    || fail "main/Mihomo architecture mismatch: $architectures vs $mihomo_architectures"
[[ "$runtime_architecture" == "$architectures" ]] \
    || fail "manifest/Mihomo architecture mismatch: $runtime_architecture vs $architectures"
[[ "$architectures" == "arm64" || "$architectures" == "x86_64" ]] \
    || fail "application must contain exactly one supported architecture: $architectures"
if [[ -n "${VIASIX_EXPECTED_ARCHITECTURE:-}" && " $architectures " != *" $VIASIX_EXPECTED_ARCHITECTURE "* ]]; then
    fail "expected architecture $VIASIX_EXPECTED_ARCHITECTURE, found $architectures"
fi

actual_mihomo_sha256=$(shasum -a 256 "$mihomo_path" | awk '{print $1}')
[[ "$actual_mihomo_sha256" == "$runtime_sha256" ]] \
    || fail "privileged Mihomo SHA-256 does not match the sealed manifest"
[[ "$actual_mihomo_cdhash" == "$runtime_cdhash" ]] \
    || fail "privileged Mihomo CDHash does not match the sealed manifest"

case "$architectures" in
    arm64) expected_mihomo_reported_architecture="arm64" ;;
    x86_64) expected_mihomo_reported_architecture="amd64" ;;
esac
mihomo_version_output=$("$mihomo_path" -v 2>&1) \
    || fail "privileged Mihomo version probe failed"
mihomo_version_line=${mihomo_version_output%%$'\n'*}
expected_mihomo_version_prefix="Mihomo Meta v${runtime_version} darwin ${expected_mihomo_reported_architecture} "
[[ "$mihomo_version_line" == ${expected_mihomo_version_prefix}* ]] \
    || fail "unexpected privileged Mihomo version output: $mihomo_version_line"
print "Verified $app_bundle ($bundle_identifier $short_version ($build_version), macOS $minimum_system+, $architectures)"
