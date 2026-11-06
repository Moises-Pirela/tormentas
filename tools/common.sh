# Shared helpers for the macOS shell scripts. Source this file; do not execute it.
# Mirrors tools/common.ps1: toolchain pin check and clockwork snapshot verification.
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOLS_DIR/.." && pwd)"
ODIN_BIN=""

log() { printf '%s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required tool not found on PATH: $cmd"
    done
}

json_get() {
    # json_get FILE DOTTED.KEY -> prints the scalar at that path.
    python3 -I -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
' "$1" "$2"
}

json_entries() {
    # json_entries FILE DOTTED.KEY -> prints "key<TAB>value" for each member of an object.
    python3 -I -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
for k, v in value.items():
    print(f"{k}\t{v}")
' "$1" "$2"
}

sha256_file() {
    shasum -a 256 "$1" | cut -d' ' -f1
}

resolve_odin() {
    # resolve_odin [PATH]; honours $ODIN, then PATH, then $HOME/odin (tools/setup-macos.sh default).
    local requested="${1:-${ODIN:-}}" candidate=""
    if [ -n "$requested" ]; then
        candidate="$requested"
    elif command -v odin >/dev/null 2>&1; then
        candidate="$(command -v odin)"
    elif [ -x "${ODIN_HOME:-$HOME/odin}/odin" ]; then
        candidate="${ODIN_HOME:-$HOME/odin}/odin"
    fi
    [ -n "$candidate" ] || die "Odin not found. Run tools/setup-macos.sh, put odin on PATH, or set ODIN=/path/to/odin. See docs/SETUP-MACOS.md."
    if [ -d "$candidate" ] && [ -x "$candidate/odin" ]; then candidate="$candidate/odin"; fi
    [ -x "$candidate" ] || die "Odin compiler is not executable: $candidate"

    local lock="$REPO_ROOT/toolchain.json" release revision version
    release="$(json_get "$lock" odin_release)"
    revision="$(json_get "$lock" odin_revision)"
    version="$("$candidate" version 2>/dev/null)" || die "Failed to run '$candidate version'."
    case "$version" in
        *"$revision"*) ;;
        *) die "Expected Odin $release revision $revision; found: $version. See docs/SETUP-MACOS.md." ;;
    esac
    ODIN_BIN="$candidate"
}

assert_manifest() {
    # assert_manifest LABEL MANIFEST.json FILES_DIR -> every sha256 entry must match a file in FILES_DIR.
    local label="$1" manifest="$2" dir="$3" name expected actual
    [ -f "$manifest" ] || die "$label manifest missing: $manifest"
    while IFS="$(printf '\t')" read -r name expected; do
        [ -f "$dir/$name" ] || die "$label snapshot file missing: $name"
        actual="$(sha256_file "$dir/$name")"
        [ "$actual" = "$expected" ] || die "$label snapshot mismatch: $name"
    done < <(json_entries "$manifest" sha256)
}

assert_clockwork_snapshot() {
    local base="$REPO_ROOT/deps/clockwork-ecs" files entries
    files="$(find "$base/clockwork" -maxdepth 1 -type f -name '*.odin' | wc -l | tr -d ' ')"
    entries="$(json_entries "$base/snapshot.json" sha256 | wc -l | tr -d ' ')"
    [ "$files" = "$entries" ] || die "clockwork snapshot file count differs from snapshot.json."
    assert_manifest clockwork "$base/snapshot.json" "$base/clockwork"
}

assert_imgui_snapshot() {
    local base="$REPO_ROOT/deps/imgui" name expected actual
    [ -f "$base/snapshot.json" ] || die "imgui manifest missing: $base/snapshot.json"
    while IFS="$(printf '\t')" read -r name expected; do
        [ -f "$base/$name" ] || die "imgui snapshot file missing: $name"
        actual="$(sha256_file "$base/$name")"
        [ "$actual" = "$expected" ] || die "imgui snapshot mismatch: $name"
    done < <(json_entries "$base/snapshot.json" sha256)
}

ensure_imgui_lib() {
    local tag lib
    case "$(uname -m)" in arm64) tag=arm64 ;; *) tag=x64 ;; esac
    lib="$REPO_ROOT/deps/imgui/imgui/imgui_darwin_${tag}.a"
    if [ ! -f "$lib" ] || [ "$REPO_ROOT/deps/imgui/snapshot.json" -nt "$lib" ] || [ "$TOOLS_DIR/build-imgui.sh" -nt "$lib" ]; then
        "$TOOLS_DIR/build-imgui.sh" --arch "$(uname -m)"
    else
        assert_imgui_snapshot
    fi
}

assert_clay_snapshot() {
    assert_manifest clay "$REPO_ROOT/clay/upstream/snapshot.json" "$REPO_ROOT/clay/upstream"
}

clay_lib_dir_for_arch() {
    case "$1" in
        arm64)  printf '%s\n' "$REPO_ROOT/clay/macos-arm64" ;;
        x86_64) printf '%s\n' "$REPO_ROOT/clay/macos" ;;
        *) die "Unsupported macOS architecture: $1" ;;
    esac
}

ensure_clay_lib() {
    # Builds the Clay static library for the host architecture if it is missing or stale.
    local arch lib
    arch="$(uname -m)"
    lib="$(clay_lib_dir_for_arch "$arch")/clay.a"
    if [ ! -f "$lib" ] || [ "$REPO_ROOT/clay/upstream/clay.h" -nt "$lib" ] || [ "$TOOLS_DIR/build-clay.sh" -nt "$lib" ]; then
        "$TOOLS_DIR/build-clay.sh" --arch "$arch"
    else
        assert_clay_snapshot
    fi
}
