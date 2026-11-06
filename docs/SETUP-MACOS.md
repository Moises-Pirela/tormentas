# Reproducible macOS setup

The macOS port uses the same pinned compiler as Windows: **Odin dev-2026-10, revision
84bc3fc**. `toolchain.json` records the official Apple silicon archive and its SHA-256,
and the scripts reject any other revision.

## Requirements

- macOS 11 or newer on Apple silicon. Odin publishes macOS archives for arm64 only; on an
  Intel Mac build Odin from source and point `ODIN` at it. The Clay library builder
  already produces `clay/macos/clay.a` for x86_64.
- Xcode Command Line Tools (`xcode-select --install`) for `clang`, `ar` and the system
  linker. Nothing from Homebrew is required.
- `python3`, `curl`, `tar` and `shasum` (all ship with macOS and the Command Line Tools).

## Install the toolchain

```sh
tools/setup-macos.sh            # installs Odin into ~/odin and builds the Clay libraries
tools/setup-macos.sh --dest ~/sdk/odin   # alternative location (or set ODIN_HOME)
```

The script downloads `odin-macos-arm64-dev-2026-10.tar.gz` from the official GitHub
release, verifies the SHA-256 from `toolchain.json`, unpacks it, confirms `odin version`
reports revision `84bc3fc`, and then runs `tools/build-clay.sh --arch all`. The release
is self-contained: it bundles LLVM and the raylib and rlgl vendor libraries.

Afterwards either add the install directory to `PATH` or export `ODIN=~/odin/odin`.
`build.sh` and `test.sh` look for `--odin PATH`, then `$ODIN`, then `odin` on `PATH`,
then `~/odin/odin`.

## Libraries

| Library | Source on macOS |
| --- | --- |
| raylib 6.0 / rlgl | `vendor/raylib/macos/libraylib.a` from the pinned Odin archive (universal arm64 + x86_64). Linked statically together with the Cocoa, OpenGL and IOKit frameworks. No install needed. |
| Dear ImGui 1.92.8-docking | `deps/imgui`: upstream C++ sources, dear_bindings C wrappers and the odin-imgui binding, hash-verified against `deps/imgui/snapshot.json`. `tools/build-imgui.sh` compiles `imgui_darwin_arm64.a` (and `imgui_darwin_x64.a`) on first build. Used only by the developer tools. |
| clockwork | `deps/clockwork-ecs`, hash-verified against `snapshot.json` exactly as on Windows. |
| Clay | Compiled from `clay/upstream/clay.h` by `tools/build-clay.sh` into `clay/macos-arm64/clay.a` (and `clay/macos/clay.a` for x86_64). `clay/clay.odin` already selects these paths for Darwin. |

### Clay snapshot

`clay/upstream/` holds the exact Clay header the Odin binding was written against:
upstream commit `3be87f190b0cb43ee197dc9e9ea70247eaf19e74` (2026-03-30, zlib license).
The v0.14 release is **not** compatible: the binding calls `Clay__OpenElementWithId`,
`Clay__HashStringWithOffset` and `Clay__GetParentElementId`, which were added after the
tag, and commits after 2026-03-30 introduce the transitions API with a different struct
layout. The symbol set of this commit matches the checked-in `clay/windows/clay.lib`.
`clay/upstream/snapshot.json` records the commit and SHA-256 hashes; the build script
verifies them before compiling. Built `.a` files are ignored by git and rebuilt when the
header or the builder script changes.

## Build, test, run

```sh
./test.sh              # clockwork, protocol and game suites (14 tests)
./build.sh             # debug build: -o:none -debug -vet  -> bin/tormentas (+ bin/tormentas.dSYM)
./run.sh               # launch from the repository root; arguments pass through (hostlocal / joinlocal)
./build.sh release     # -o:aggressive -vet, then packages dist/macos/Tormentas.app
```

The scripts resolve paths from their own location and can be invoked from another
directory. `-linker:lld`, `-subsystem:windows` and the `.rc` resource are Windows-only
and are not passed on macOS.

## Release packaging

`./build.sh release` produces:

- `dist/macos/Tormentas.app` with the binary and `data/` inside `Contents/MacOS/`,
  an `Info.plist`, an `.icns` generated from `data/app/tormentas_icon.png`, and the
  `LICENSE` in `Contents/Resources/`. The bundle is ad-hoc code signed.
- `dist/tormentas-macos-release.zip`, created with `ditto` so bundle metadata survives.

`data/` sits next to the executable because `src/main.odin` uses the executable's
directory as the working directory when that directory is not named `bin`. Nothing is
written inside the bundle: saves and settings live in
`~/Library/Application Support/Tormentas/` (`save/characters.bin`, `config.json`). Writing
into the bundle would invalidate its code signature, and macOS runs downloaded apps from a
read-only translocated copy. Saves from earlier macOS builds in `save/` next to the
executable are copied over on first launch. On Windows the paths are unchanged.

The bundle is ad-hoc signed only. A downloaded copy will be blocked by Gatekeeper until it
is signed with a Developer ID certificate and notarized; for local testing, right-click the
app and choose Open.

Override the bundle identifier or marketing version with `TORMENTAS_BUNDLE_ID` and
`TORMENTAS_VERSION`; `CFBundleVersion` is the git commit count.

## Window and display

- The window is resizable (minimum 960 × 540) and the whole UI scales with its height.
- macOS opens in native fullscreen by default: the game gets its own Space and the desktop
  resolution is not changed. Toggle with **Ctrl + Cmd + F**, the green window button, or
  Settings → Window Mode. The choice and the last windowed size are saved in `config.json`.
- Windowed sizes are clamped to fit the current display.
- Rendering is at the display's point resolution (1440 × 900 on a 2560 × 1600 Retina
  panel), which macOS upscales. raylib's HighDPI mode is **not** enabled: with it the HUD is
  sharp but the lighting and sprite composites are drawn at the wrong scale and offset.
  Supporting Retina needs those render targets and shaders to work in framebuffer pixels.
- Keyboard labels use Mac names (Opt, Cmd). Editor and animation-editor shortcuts accept
  Cmd as well as Ctrl. Cmd+Q quits through the normal shutdown path, so a raid in progress
  counts as abandoned.

### Window probe

`bin/tormentas --window-probe <dir>` starts a throwaway character in the hub, steps through
fullscreen → windowed → resize → oversize → fullscreen, logs window, render and monitor sizes,
writes framebuffer screenshots to `<dir>`, and exits. Its saves and config go to
`<dir>/userdata`, never to the real user folder. Use it to check display changes without a
person at the keyboard.

## Optional Steam

Pass `--enable-steam` (and optionally `--steam-collection DIR`, default `.local/`). The
collection must contain `steamworks/steamworks.odin` and
`steamworks/redistributable_bin/osx/libsteam_api.dylib` from a Steamworks SDK you are
licensed to use; the dylib is copied next to the binary and into the app bundle. The
Odin binding must declare the Darwin foreign import itself. See
[STEAMWORKS.md](STEAMWORKS.md) for the sharing rules. Automated tests always use the
disabled transport in `deps/offline`.
