#!/usr/bin/env bash
# Builds the Dear ImGui static library for macOS from the pinned sources in deps/imgui/src.
# deps/imgui/imgui/lib_name.odin links imgui_darwin_arm64.a on Apple silicon and
# imgui_darwin_x64.a on Intel.
#
# usage: tools/build-imgui.sh [--arch arm64|x86_64|all] [--force]
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

[ "$(uname -s)" = Darwin ] || die "build-imgui.sh builds macOS libraries only."
require_cmd clang++ ar nm shasum python3
assert_imgui_snapshot

SRC="$REPO_ROOT/deps/imgui/src"
SOURCES="imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp imgui_demo.cpp
dcimgui_nodefaultargfunctions.cpp dcimgui_nodefaultargfunctions_internal.cpp"
REQUIRED_SYMBOLS="ImGui_CreateContext ImGui_NewFrame ImGui_Render ImGui_GetDrawData ImGui_Begin
ImGui_DockSpaceOverViewport ImGui_GetIO ImGui_GetPlatformIO ImFontAtlas_AddFontFromFileTTF"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for arch in $ARCHES; do
    case "$arch" in arm64) tag=arm64 ;; x86_64) tag=x64 ;; *) die "Unsupported arch: $arch" ;; esac
    out="$REPO_ROOT/deps/imgui/imgui/imgui_darwin_${tag}.a"
    if [ "$FORCE" -eq 0 ] && [ -f "$out" ] && [ "$out" -nt "$REPO_ROOT/deps/imgui/snapshot.json" ] && [ "$out" -nt "${BASH_SOURCE[0]}" ]; then
        log "[IMGUI] up to date: $out"
        continue
    fi
    log "[IMGUI] compiling Dear ImGui for $arch"
    mkdir -p "$TMP/$arch"
    for s in $SOURCES; do
        clang++ -std=c++11 -O2 -arch "$arch" -mmacosx-version-min=11.0 \
            -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS '-DIMGUI_IMPL_API=extern "C"' \
            -fno-exceptions -fno-rtti -fno-threadsafe-statics \
            -I"$SRC" -c "$SRC/$s" -o "$TMP/$arch/${s%.cpp}.o"
    done
    rm -f "$TMP/lib_$arch.a"
    ar rcs "$TMP/lib_$arch.a" "$TMP/$arch"/*.o
    syms="$(nm -g "$TMP/lib_$arch.a" 2>/dev/null)"
    for sym in $REQUIRED_SYMBOLS; do
        grep -q " T _${sym}\$" <<<"$syms" || die "Built ImGui library is missing symbol $sym"
    done
    mv "$TMP/lib_$arch.a" "$out"
    log "[IMGUI] OK -> $out"
done
