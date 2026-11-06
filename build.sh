#!/usr/bin/env bash
# macOS build for Las Tormentas. Counterpart of build.ps1.
#
# usage: ./build.sh [debug|release] [--odin PATH] [--enable-steam] [--steam-collection DIR]
#
#   debug    (default) -o:none -debug -vet            -> bin/tormentas
#   release  -o:aggressive -vet, then packages        -> dist/macos/Tormentas.app
#                                                        dist/tormentas-macos-release.zip
#
# Raylib, rlgl and microui come from the pinned Odin toolchain (vendor/). The Clay UI
# library is compiled from clay/upstream/clay.h on first use (tools/build-clay.sh).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/common.sh"

MODE=debug
ODIN_PATH=""
ENABLE_STEAM=0
STEAM_COLLECTION="$REPO_ROOT/.local"
while [ $# -gt 0 ]; do
    case "$1" in
        debug|release) MODE="$1"; shift ;;
        --odin) [ $# -ge 2 ] || die "--odin needs a value"; ODIN_PATH="$2"; shift 2 ;;
        --enable-steam) ENABLE_STEAM=1; shift ;;
        --steam-collection) [ $# -ge 2 ] || die "--steam-collection needs a value"; STEAM_COLLECTION="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $1 (expected debug|release, --odin, --enable-steam, --steam-collection)" ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die "build.sh targets macOS. Use build.ps1 on Windows."
require_cmd python3 shasum clang
resolve_odin "$ODIN_PATH"
assert_clockwork_snapshot
ensure_clay_lib
ensure_imgui_lib

OUT="$REPO_ROOT/bin/tormentas"
CW="$REPO_ROOT/deps/clockwork-ecs"
STEAM="$REPO_ROOT/deps/offline"
FLAGS=(-o:none -debug -vet)
[ "$MODE" = release ] && FLAGS=(-o:aggressive -vet)

STEAM_DYLIB=""
if [ "$ENABLE_STEAM" -eq 1 ]; then
    STEAM="$(cd "$STEAM_COLLECTION" 2>/dev/null && pwd)" || die "Steam collection not found: $STEAM_COLLECTION. See docs/STEAMWORKS.md."
    for required in steamworks/steamworks.odin steamworks/redistributable_bin/osx/libsteam_api.dylib; do
        [ -f "$STEAM/$required" ] || die "Missing optional Steam dependency: $required. See docs/STEAMWORKS.md."
    done
    STEAM_DYLIB="$STEAM/steamworks/redistributable_bin/osx/libsteam_api.dylib"
    FLAGS+=(-define:STEAM_ENABLED=true)
fi

mkdir -p "$REPO_ROOT/bin"
log "[BUILD] odin build src ($MODE) with $ODIN_BIN"
"$ODIN_BIN" build "$REPO_ROOT/src" "-out:$OUT" "-collection:cw=$CW" "-collection:steam=$STEAM" "${FLAGS[@]}"
if [ -n "$STEAM_DYLIB" ]; then
    cp -f "$STEAM_DYLIB" "$REPO_ROOT/bin/libsteam_api.dylib"
fi
log "[BUILD] OK -> $OUT (Steam enabled: $ENABLE_STEAM)"
[ "$MODE" = release ] || exit 0

# ---- Release packaging: Tormentas.app + zip --------------------------------------------
# The game resolves its working directory from the executable's location (src/main.odin):
# a binary inside a directory not named "bin" uses that directory as cwd, so data/ lives
# next to the binary inside Contents/MacOS.
DIST="$REPO_ROOT/dist/macos"
APP="$DIST/Tormentas.app"
ZIP="$REPO_ROOT/dist/tormentas-macos-release.zip"
BUNDLE_ID="${TORMENTAS_BUNDLE_ID:-com.protomutant.tormentas}"
SHORT_VERSION="${TORMENTAS_VERSION:-0.1.0}"
BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
case "$DIST" in "$REPO_ROOT"/dist/*) ;; *) die "Invalid distribution path: $DIST" ;; esac

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT" "$APP/Contents/MacOS/tormentas"
cp -R "$REPO_ROOT/data" "$APP/Contents/MacOS/data"
cp "$REPO_ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
[ -n "$STEAM_DYLIB" ] && cp -f "$STEAM_DYLIB" "$APP/Contents/MacOS/libsteam_api.dylib"

ICON_KEY=""
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$DIST/tormentas.iconset"
    mkdir -p "$ICONSET"
    SRC_ICON="$REPO_ROOT/data/app/tormentas_icon.png"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$SRC_ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/tormentas.icns"; then
        ICON_KEY="    <key>CFBundleIconFile</key><string>tormentas</string>"
    fi
    rm -rf "$ICONSET"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Las Tormentas</string>
    <key>CFBundleExecutable</key><string>tormentas</string>
${ICON_KEY}
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Tormentas</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" 2>/dev/null || log "[PACKAGE] ad-hoc codesign skipped"
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
log "[PACKAGE] $APP"
log "[PACKAGE] $ZIP"
