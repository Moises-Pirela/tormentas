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
