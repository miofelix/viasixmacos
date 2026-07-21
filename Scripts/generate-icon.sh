#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
source_svg=${1:-"$project_root/Packaging/AppIcon.svg"}
output_icns=${2:-"$project_root/dist/AppIcon.icns"}

if [[ ! -f "$source_svg" ]]; then
    print -u2 "App icon source not found: $source_svg"
    exit 1
fi

icon_workspace=$(mktemp -d "${TMPDIR:-/tmp}/viasix-icon.XXXXXX")
trap 'rm -rf "$icon_workspace"' EXIT

base_png="$icon_workspace/AppIcon-1024.png"
iconset="$icon_workspace/AppIcon.iconset"
mkdir -p "$iconset" "${output_icns:h}"

/usr/bin/sips -s format png --resampleHeightWidth 1024 1024 "$source_svg" --out "$base_png" >/dev/null

for specification in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size=${specification%% *}
    filename=${specification#* }
    /usr/bin/sips --resampleHeightWidth "$size" "$size" "$base_png" \
        --out "$iconset/$filename" >/dev/null
done

/usr/bin/iconutil -c icns "$iconset" -o "$output_icns"
print "Created $output_icns"
