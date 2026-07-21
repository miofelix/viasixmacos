#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
failures=0

check_document() {
    local document=$1
    local reference target resolved

    while IFS= read -r reference; do
        target=${reference#*\(}
        target=${target%\)}

        if [[ "$target" == \<*\> ]]; then
            target=${target#\<}
            target=${target%%\>*}
        else
            target=${target%%[[:space:]]*}
        fi

        [[ -z "$target" || "$target" == \#* ]] && continue
        [[ "$target" == *://* || "$target" == mailto:* ]] && continue

        target=${target%%\#*}
        target=${target//%20/ }
        resolved="${document:h}/$target"

        if [[ ! -e "$resolved" ]]; then
            print -u2 "Broken local link in ${document#$project_root/}: $target"
            (( failures += 1 ))
        fi
    done < <(LC_ALL=C grep -E -o '\]\([^)]*\)' "$document" || true)
}

if (( $# == 0 )); then
    while IFS= read -r -d '' document; do
        check_document "$document"
    done < <(
        find "$project_root" \
            \( -path "$project_root/.build" -o -path "$project_root/.git" -o -path "$project_root/dist" \) -prune \
            -o -type f -name '*.md' -print0
    )
else
    while IFS= read -r -d '' document; do
        check_document "$document"
    done < <(find "$@" -type f -name '*.md' -print0)
fi

if (( failures > 0 )); then
    print -u2 "$failures broken local Markdown link(s) found"
    exit 1
fi

print "Markdown links verified"
