#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
configuration=${1:-release}
app_bundle="$project_root/dist/ViaSix.app"
contents_dir="$app_bundle/Contents"

case "$configuration" in
    debug|release) ;;
    *)
        print -u2 "Unsupported configuration: $configuration (expected debug or release)"
        exit 1
        ;;
esac

swift build --package-path "$project_root" -c "$configuration"
binary_directory=$(swift build --package-path "$project_root" -c "$configuration" --show-bin-path)
binary_path="$binary_directory/ViaSix"

if [[ ! -x "$binary_path" ]]; then
    print -u2 "ViaSix executable was not produced at $binary_path"
    exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_path" "$contents_dir/MacOS/ViaSix"
cp "$project_root/Packaging/Info.plist" "$contents_dir/Info.plist"
cp "$project_root/Docs/USER_GUIDE.md" "$contents_dir/Resources/USER_GUIDE.md"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$contents_dir/Resources/THIRD_PARTY_NOTICES.md"
"$project_root/Scripts/generate-icon.sh" \
    "$project_root/Packaging/AppIcon.svg" \
    "$contents_dir/Resources/AppIcon.icns"

resource_bundles=("$binary_directory"/ViaSix_*.bundle(N))
if (( ${#resource_bundles} == 0 )); then
    print -u2 "ViaSix resource bundle was not produced in $binary_directory"
    exit 1
fi

# The app resolves packaged defaults through Bundle.main before SwiftPM's
# development-only Bundle.module fallback, so copy the payload into the normal
# macOS application resources directory.
for resource_bundle in "${resource_bundles[@]}"; do
    for resource in "$resource_bundle"/*(N); do
        [[ "${resource:t}" == "Info.plist" ]] && continue
        ditto "$resource" "$contents_dir/Resources/${resource:t}"
    done
done

chmod 755 "$contents_dir/MacOS/ViaSix"
codesign_identity=${VIASIX_CODESIGN_IDENTITY:--}
if [[ "$codesign_identity" == "-" ]]; then
    codesign --force --sign - "$app_bundle"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$codesign_identity" \
        "$app_bundle"
fi

"$project_root/Scripts/verify-app.sh" "$app_bundle"

print "Created $app_bundle"
