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

assert_sokol_snapshot() {
    # Every vendored binding/header must match deps/sokol/snapshot.json, and nothing unlisted may sneak in.
    local base="$REPO_ROOT/deps/sokol" files entries
    assert_manifest sokol "$base/snapshot.json" "$base"
    files="$(cd "$base" && find sokol -type f \( -name '*.odin' -o -name '*.c' -o -name '*.h' \) | wc -l | tr -d ' ')"
    entries="$(json_entries "$base/snapshot.json" sha256 | grep -c '^sokol/' | tr -d ' ')"
    [ "$files" = "$entries" ] || die "sokol snapshot file count ($files) differs from snapshot.json ($entries)."
}

ensure_sokol_libs() {
    # Builds the sokol static libraries for the host architecture if any is missing or stale.
    local tag lib m stale=0
    case "$(uname -m)" in arm64) tag=arm64 ;; *) tag=x64 ;; esac
    for m in log gfx app glue time gl shape; do
        for mode in debug release; do
            lib="$REPO_ROOT/deps/sokol/sokol/$m/sokol_${m}_macos_${tag}_metal_${mode}.a"
            if [ ! -f "$lib" ] || [ "$REPO_ROOT/deps/sokol/snapshot.json" -nt "$lib" ] || [ "$TOOLS_DIR/build-sokol.sh" -nt "$lib" ]; then
                stale=1
            fi
        done
    done
    if [ "$stale" -eq 1 ]; then
        "$TOOLS_DIR/build-sokol.sh" --arch "$(uname -m)"
    else
        assert_sokol_snapshot
    fi
}

SHDC_BIN=""
ensure_shdc() {
    # Downloads the pinned sokol-shdc into .local/sokol-shdc/<commit>/ (once) and verifies its hash.
    local manifest="$REPO_ROOT/deps/sokol/snapshot.json" plat commit path expected dest actual
    case "$(uname -m)" in arm64) plat=macos_arm64 ;; *) plat=macos_x64 ;; esac
    commit="$(json_get "$manifest" sokol_shdc.commit)"
    path="$(json_get "$manifest" "sokol_shdc.platforms.$plat.path")"
    expected="$(json_get "$manifest" "sokol_shdc.platforms.$plat.sha256")"
    dest="$REPO_ROOT/.local/sokol-shdc/$commit/sokol-shdc"
    if [ ! -x "$dest" ]; then
        require_cmd curl
        mkdir -p "$(dirname "$dest")"
        log "[SHDC] downloading sokol-shdc $commit ($plat)"
        curl -fsSL "https://raw.githubusercontent.com/floooh/sokol-tools-bin/$commit/$path" -o "$dest.part" \
            || die "sokol-shdc download failed"
        actual="$(sha256_file "$dest.part")"
        [ "$actual" = "$expected" ] || { rm -f "$dest.part"; die "sokol-shdc hash mismatch: got $actual"; }
        chmod +x "$dest.part"
        mv "$dest.part" "$dest"
    fi
    actual="$(sha256_file "$dest")"
    [ "$actual" = "$expected" ] || die "sokol-shdc at $dest does not match snapshot.json"
    SHDC_BIN="$dest"
}

compile_shaders() {
    # compile_shaders DIR -> regenerates <name>.glsl.odin next to every <name>.glsl under DIR that is
    # newer than its output. Targets the two decided backends: Metal (macOS) and D3D11 (Windows).
    local dir="$1" src out
    while IFS= read -r src; do
        out="$src.odin"
        if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
            [ -n "$SHDC_BIN" ] || ensure_shdc
            log "[SHDC] ${src#"$REPO_ROOT"/} -> ${out#"$REPO_ROOT"/}"
            "$SHDC_BIN" -i "$src" -o "$out" -l metal_macos:hlsl5 -f sokol_odin || die "sokol-shdc failed on $src"
        fi
    done < <(find "$dir" -name '*.glsl' -type f | sort)
}

ensure_capture_lib() {
    # Builds the Metal readback helper used for screenshots (src/gfx/native/capture_metal.m).
    local arch tag native out
    arch="$(uname -m)"
    case "$arch" in arm64) tag=arm64 ;; *) tag=x64 ;; esac
    native="$REPO_ROOT/src/gfx/native"
    out="$native/capture_metal_$tag.a"
    if [ ! -f "$out" ] || [ "$native/capture_metal.m" -nt "$out" ]; then
        log "[BUILD] native/capture_metal.m ($tag)"
        local tmp
        tmp="$(mktemp -d)"
        clang -c -fobjc-arc -O2 -arch "$arch" -mmacosx-version-min=11.0 "$native/capture_metal.m" -o "$tmp/capture_metal.o"
        rm -f "$out"
        ar rcs "$out" "$tmp/capture_metal.o"
        rm -rf "$tmp"
    fi
}
