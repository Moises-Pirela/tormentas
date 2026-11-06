#!/usr/bin/env bash
# Launches Las Tormentas from the repository root. Extra arguments are passed to the game
# (for example: ./run.sh hostlocal 27600). The default build runs without Steam.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -x bin/tormentas ] || { echo "bin/tormentas not found. Run ./build.sh first." >&2; exit 1; }
exec bin/tormentas "$@"
