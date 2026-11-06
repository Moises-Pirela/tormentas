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
run_suite src game
log "[TEST] all suites passed"
