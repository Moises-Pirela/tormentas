#!/usr/bin/env bash
# Runs the clockwork, protocol and game test suites on macOS. Counterpart of test.ps1.
#
# usage: ./test.sh [--odin PATH]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/common.sh"

ODIN_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --odin) [ $# -ge 2 ] || die "--odin needs a value"; ODIN_PATH="$2"; shift 2 ;;
        -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die "test.sh targets macOS. Use test.ps1 on Windows."
require_cmd python3 shasum clang
resolve_odin "$ODIN_PATH"
assert_clockwork_snapshot
ensure_clay_lib
ensure_imgui_lib

mkdir -p "$REPO_ROOT/bin"
CW="$REPO_ROOT/deps/clockwork-ecs"
OFFLINE="$REPO_ROOT/deps/offline"
run_suite() {
    local path="$1" name="$2"
    log "[TEST] $name ($path)"
    "$ODIN_BIN" test "$REPO_ROOT/$path" "-collection:cw=$CW" "-collection:steam=$OFFLINE" -vet \
        -define:ODIN_TEST_THREADS=1 "-out:$REPO_ROOT/bin/${name}_tests"
}
run_suite deps/clockwork-ecs/clockwork clockwork
run_suite src/p2p protocol
run_suite src/sim sim
run_suite src game

# Headless server: import boundaries, build, no graphics/audio/UI/Steam linked in, and it runs.
log "[TEST] headless server"
"$REPO_ROOT/build.sh" server --odin "$ODIN_BIN"
SERVER_BIN="$REPO_ROOT/bin/tormentas_server"
FORBIDDEN='glfw|InitWindow|raylib|ImGui|Clay_|SteamAPI|ma_device'
# Capture first: under `set -o pipefail`, `nm | grep -q` reports failure on a match (nm gets SIGPIPE).
SERVER_SYMS="$(nm "$SERVER_BIN")"
if grep -qiE "$FORBIDDEN" <<<"$SERVER_SYMS"; then
    grep -iE "$FORBIDDEN" <<<"$SERVER_SYMS" | head -5 >&2
    die "headless server links client-only symbols (see above). Something in src/sim or src/server pulls in graphics, audio, UI or Steam."
fi
"$SERVER_BIN" --ticks 600
log "[TEST] all suites passed"
