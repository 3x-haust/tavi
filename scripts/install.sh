#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
app="${1:-/Applications/Tavi.app}"

if [[ ! -d "$app" && -d "$project_root/dist/Tavi.app" ]]; then
    app="$project_root/dist/Tavi.app"
fi

if [[ ! -d "$app" ]]; then
    printf 'Tavi.app was not found. Drag Tavi.app to Applications, then open it normally.\n' >&2
    exit 1
fi

printf 'Opening Tavi. Complete input-method setup inside the app.\n'
open "$app"
