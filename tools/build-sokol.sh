#!/usr/bin/env bash
# Builds the sokol static libraries for macOS (Metal) from the pinned headers in deps/sokol/sokol/c.
# Each binding in deps/sokol/sokol/<module>/ links <module>/sokol_<module>_macos_<arch>_metal_<mode>.a,
# picking debug or release from ODIN_DEBUG, so both variants are built.
#
# usage: tools/build-sokol.sh [--arch arm64|x86_64|all] [--force]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ARCHES="$(uname -m)"
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) [ $# -ge 2 ] || die "--arch needs a value"; ARCHES="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[ "$ARCHES" = all ] && ARCHES="arm64 x86_64"

[ "$(uname -s)" = Darwin ] || die "build-sokol.sh builds macOS libraries only."
require_cmd clang ar nm shasum python3
assert_sokol_snapshot

BASE="$REPO_ROOT/deps/sokol/sokol"
MODULES="log gfx app glue time gl shape"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for arch in $ARCHES; do
    case "$arch" in arm64) tag=arm64 ;; x86_64) tag=x64 ;; *) die "Unsupported arch: $arch" ;; esac
    for mode in debug release; do
        case "$mode" in debug) cflags=(-g) ;; release) cflags=(-O2 -DNDEBUG) ;; esac
        for m in $MODULES; do
            out="$BASE/$m/sokol_${m}_macos_${tag}_metal_${mode}.a"
            if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$REPO_ROOT/deps/sokol/snapshot.json" ] && [ "$out" -nt "${BASH_SOURCE[0]}" ]; then
                continue
            fi
            log "[SOKOL] compiling sokol_$m ($arch, $mode)"
            obj="$TMP/sokol_${m}_${tag}_${mode}.o"
            MACOSX_DEPLOYMENT_TARGET=11.0 clang -c "${cflags[@]}" -x objective-c -arch "$arch" \
                -DIMPL -DSOKOL_METAL "$BASE/c/sokol_$m.c" -o "$obj"
            rm -f "$out"
            ar rcs "$out" "$obj"
            nm -g "$out" 2>/dev/null | grep -q " T _s" || die "Built sokol_$m library exports no symbols"
        done
    done
    log "[SOKOL] OK -> $BASE/*/sokol_*_macos_${tag}_metal_{debug,release}.a"
done
