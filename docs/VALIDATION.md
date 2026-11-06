# Validation performed on 2026-10-31

Toolchain: Windows x64, Odin dev-2026-10 revision 84bc3fc, LLVM lld.

- `test.ps1 -OdinPath C:\ODIN\odin.exe`: **14 tests passed** across clockwork (4),
  production protocol code (7) and game logic (3), with memory tracking enabled.
- Default debug build with vetting: passed.
- Default optimized release build and packaging: passed.
- Optional Steam debug build against the preserved private binding and libraries:
  compiled and linked; no live Steam session was tested.
- Exported `dist/tormentas-source.zip`, extracted it into a separate directory,
  then ran its test and debug build scripts successfully. This confirms the
  submission does not depend on the private checkout or local Steam files.
- Inspected source archive entries: no original `steamworks/`, `.local/`, `.git/`,
  generated executables or runtime libraries.
- Inspected offline release ZIP and executable PE import table: no Steam runtime
  files or Steam DLL dependency.
- `git diff --check`: passed.

The complete-snapshot regression test was first run against the old parser and
failed because truncated input cleared the previous snapshot. It passed after
validating the full payload size and entity count before mutation.

This validation does not include a visual playthrough, audio checks or live co-op.

# macOS validation performed on 2026-11-06

Toolchain: macOS 26.6 on Apple M1 (arm64), Odin dev-2026-10 revision 84bc3fc from the
official `odin-macos-arm64` archive, Apple clang 21, system linker.

- `tools/setup-macos.sh --dest <dir>`: downloaded the archive, verified its SHA-256
  against `toolchain.json`, confirmed the revision, and built both Clay libraries.
- `tools/build-clay.sh --arch all`: compiled `clay/upstream/clay.h` with
  `-std=c99 -O2 -Wall -Wextra` without warnings for arm64 and x86_64; all symbols the
  binding imports are present. Tampering with the header is rejected by the manifest check.
- `./test.sh`: **14 tests passed** across clockwork (4), protocol (7) and game (3),
  with memory tracking enabled.
- `./build.sh` (debug, `-vet`): passed. The binary links Cocoa, OpenGL and IOKit only.
- `./run.sh`: the game initialized raylib 6.0 on OpenGL 4.1, loaded fonts, shaders
  (GLSL 330), sprites and levels, and ran until terminated. GLFW logs a harmless warning
  that macOS windows have no icon. Missing tile files `wall_04.png`, `water_01.png` and
  `pillar_03.png` are reported on every platform and are a content gap, not a port issue.
- `./build.sh release`: passed; produced an ad-hoc signed `dist/macos/Tormentas.app`
  (`plutil -lint` clean) and `dist/tormentas-macos-release.zip`. The bundled binary
  resolves its working directory to `Contents/MacOS` and loads `data/` from there.
- Rejection paths: a compiler with another revision, a missing compiler, and a non-empty
  install destination each fail with a message pointing at `docs/SETUP-MACOS.md`.
- `git diff --check`: passed.

Not covered: Intel Macs (the x86_64 Clay library is built but untested), the optional
Steam build on macOS, a visual playthrough, audio, and live co-op.
