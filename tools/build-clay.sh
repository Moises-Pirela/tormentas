#!/usr/bin/env bash
# Builds the Clay UI static library for macOS from the pinned header in clay/upstream.
# clay/clay.odin links clay/macos-arm64/clay.a on Apple silicon and clay/macos/clay.a on Intel.
#
# usage: tools/build-clay.sh [--arch arm64|x86_64|all] [--force]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ARCHES="$(uname -m)"
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) [ $# -ge 2 ] || die "--arch needs a value"; ARCHES="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[ "$ARCHES" = all ] && ARCHES="arm64 x86_64"

[ "$(uname -s)" = Darwin ] || die "build-clay.sh builds macOS libraries only."
require_cmd clang ar nm shasum python3
assert_clay_snapshot

HEADER="$REPO_ROOT/clay/upstream/clay.h"
MIN_OS="11.0"   # matches Odin's default -minimum-os-version for Darwin
REQUIRED_SYMBOLS="Clay_Initialize Clay_BeginLayout Clay_EndLayout Clay_SetMeasureTextFunction
Clay_GetScrollOffset Clay_ResetMeasureTextCache Clay_RenderCommandArray_Get
Clay__OpenElement Clay__OpenElementWithId Clay__CloseElement Clay__ConfigureOpenElement
Clay__HashString Clay__HashStringWithOffset Clay__GetParentElementId
Clay__OpenTextElement Clay__StoreTextElementConfig"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '#define CLAY_IMPLEMENTATION\n#include "%s"\n' "$HEADER" > "$TMP/clay_impl.c"

for arch in $ARCHES; do
    out_dir="$(clay_lib_dir_for_arch "$arch")"
    out="$out_dir/clay.a"
    if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$HEADER" ] && [ "$out" -nt "${BASH_SOURCE[0]}" ]; then
        log "[CLAY] up to date: $out"
        continue
    fi
    log "[CLAY] compiling clay.h for $arch"
    clang -std=c99 -O2 -arch "$arch" -mmacosx-version-min="$MIN_OS" -Wall -Wextra \
        -c "$TMP/clay_impl.c" -o "$TMP/clay_$arch.o"
    rm -f "$TMP/clay_$arch.a"
    ar rcs "$TMP/clay_$arch.a" "$TMP/clay_$arch.o"
    syms="$(nm -g "$TMP/clay_$arch.a")"
    for sym in $REQUIRED_SYMBOLS; do
        grep -q " T _${sym}\$" <<<"$syms" || die "Built Clay library is missing symbol $sym"
    done
    mkdir -p "$out_dir"
    mv "$TMP/clay_$arch.a" "$out"
    log "[CLAY] OK -> $out"
done
