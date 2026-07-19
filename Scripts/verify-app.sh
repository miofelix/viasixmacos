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
[[ -f "$info_plist" ]] || fail "missing Contents/Info.plist"
plutil -lint "$info_plist" >/dev/null

executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$info_plist")
bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist")
package_type=$(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$info_plist")
minimum_system=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$info_plist")
short_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist")
executable_path="$contents_dir/MacOS/$executable_name"

[[ "$bundle_identifier" == "com.felix.viasix" ]] || fail "unexpected bundle identifier: $bundle_identifier"
[[ "$package_type" == "APPL" ]] || fail "unexpected package type: $package_type"
[[ "$minimum_system" == "14.0" ]] || fail "unexpected minimum macOS version: $minimum_system"
[[ "$short_version" == "1.0.0" ]] || fail "unexpected application version: $short_version"
[[ -x "$executable_path" ]] || fail "main executable is missing or not executable"
file "$executable_path" | grep -q "Mach-O" || fail "main executable is not Mach-O"

for resource_name in ip.txt ipv6.txt template.json; do
    [[ -f "$contents_dir/Resources/$resource_name" ]] || fail "missing bundled resource: $resource_name"
done

[[ -f "$contents_dir/Resources/THIRD_PARTY_NOTICES.md" ]] || fail "missing third-party notices"
[[ -f "$contents_dir/Resources/AppIcon.icns" ]] || fail "missing application icon"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

architectures=$(lipo -archs "$executable_path")
print "Verified $app_bundle ($bundle_identifier $short_version, macOS $minimum_system+, $architectures)"
