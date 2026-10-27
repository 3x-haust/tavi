#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d dist/Tavi.app ]]; then
    bash scripts/build.sh
fi
open "$(pwd)/dist/Tavi.app"
