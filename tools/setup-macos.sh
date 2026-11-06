#!/usr/bin/env bash
# Installs the pinned Odin toolchain for macOS (Apple silicon) and builds the Clay static library.
# Downloads the official release archive named in toolchain.json, verifies its SHA-256,
# unpacks it into $HOME/odin (override with --dest or ODIN_HOME) and checks the compiler revision.
#
# usage: tools/setup-macos.sh [--dest DIR] [--force] [--skip-clay]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DEST="${ODIN_HOME:-$HOME/odin}"
FORCE=0
SKIP_CLAY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dest) [ $# -ge 2 ] || die "--dest needs a value"; DEST="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        --skip-clay) SKIP_CLAY=1; shift ;;
        -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[ "$(uname -s)" = Darwin ] || die "setup-macos.sh is for macOS only."
[ "$(uname -m)" = arm64 ] || die "Odin publishes macOS archives for Apple silicon only. On an Intel Mac build Odin from source (https://odin-lang.org/docs/install/) and set ODIN."
require_cmd curl tar shasum python3 clang
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are required for clang and the system linker. Run: xcode-select --install"

LOCK="$REPO_ROOT/toolchain.json"
RELEASE="$(json_get "$LOCK" odin_release)"
REVISION="$(json_get "$LOCK" odin_revision)"
URL="$(json_get "$LOCK" platforms.macos_arm64.url)"
ARCHIVE="$(json_get "$LOCK" platforms.macos_arm64.archive)"
EXPECTED_SHA="$(json_get "$LOCK" platforms.macos_arm64.sha256)"

TMP=""
trap '[ -n "$TMP" ] && rm -rf "$TMP"' EXIT

install_odin() {
    if [ -x "$DEST/odin" ]; then
        local version
        version="$("$DEST/odin" version 2>/dev/null || true)"
        case "$version" in
            *"$REVISION"*) log "[ODIN] already installed at $DEST ($version)"; return ;;
        esac
        if [ "$FORCE" -eq 1 ] && [ -d "$DEST/core" ] && [ -d "$DEST/base" ]; then
            log "[ODIN] replacing existing Odin install at $DEST ($version)"
            rm -rf "$DEST"
        else
            die "$DEST holds a different Odin ($version). Pass --force to replace it, or --dest to pick another directory."
        fi
    elif [ -d "$DEST" ] && [ -n "$(ls -A "$DEST")" ]; then
        die "$DEST exists and is not empty. Pass --dest to pick another directory."
    fi

    TMP="$(mktemp -d)"
    log "[ODIN] downloading $ARCHIVE"
    curl -fL --retry 3 --progress-bar -o "$TMP/$ARCHIVE" "$URL"
    local actual
    actual="$(sha256_file "$TMP/$ARCHIVE")"
    [ "$actual" = "$EXPECTED_SHA" ] || die "SHA-256 mismatch for $ARCHIVE: expected $EXPECTED_SHA, got $actual"
    log "[ODIN] checksum OK"
    mkdir -p "$TMP/x"
    tar -xzf "$TMP/$ARCHIVE" -C "$TMP/x"
    local top
    top="$(find "$TMP/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$top" ] && [ -x "$top/odin" ] || die "Unexpected archive layout in $ARCHIVE"
    mkdir -p "$DEST"
    cp -R "$top/." "$DEST/"
    chmod +x "$DEST/odin"
    log "[ODIN] installed to $DEST"
}

install_odin
VERSION="$("$DEST/odin" version)"
case "$VERSION" in
    *"$REVISION"*) log "[ODIN] $VERSION (pinned $RELEASE revision $REVISION)" ;;
    *) die "Installed compiler reports '$VERSION', expected revision $REVISION." ;;
esac

if [ "$SKIP_CLAY" -eq 0 ]; then
    "$TOOLS_DIR/build-clay.sh" --arch all
    "$TOOLS_DIR/build-imgui.sh" --arch all
fi

log ""
log "Done. Either add Odin to PATH:"
log "    export PATH=\"$DEST:\$PATH\""
log "or point the scripts at it:"
log "    export ODIN=\"$DEST/odin\""
log "Then run ./test.sh, ./build.sh and ./run.sh from the repository root."
