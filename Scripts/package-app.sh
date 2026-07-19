#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
configuration=${1:-release}
app_bundle="$project_root/dist/ViaSix.app"
contents_dir="$app_bundle/Contents"
binary_path="$project_root/.build/$configuration/ViaSix"

swift build --package-path "$project_root" -c "$configuration"

if [[ ! -x "$binary_path" ]]; then
    print -u2 "ViaSix executable was not produced at $binary_path"
    exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_path" "$contents_dir/MacOS/ViaSix"
cp "$project_root/Packaging/Info.plist" "$contents_dir/Info.plist"

for resource_bundle in "$project_root/.build/$configuration"/ViaSix_*.bundle(N); do
    for resource in "$resource_bundle"/*(N); do
        [[ "${resource:t}" == "Info.plist" ]] && continue
        ditto "$resource" "$contents_dir/Resources/${resource:t}"
    done
done

chmod 755 "$contents_dir/MacOS/ViaSix"
codesign --force --deep --sign - "$app_bundle"

print "Created $app_bundle"
