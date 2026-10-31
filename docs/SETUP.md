# Reproducible Windows setup

1. Download the **Windows amd64** archive from the official
   [Odin dev-2026-10 release](https://github.com/odin-lang/Odin/releases/tag/dev-2026-10).
   Extract the complete archive, including `core`, `vendor`, `bin` and LLVM files.
   Required compiler revision: **84bc3fc**. `toolchain.json` pins it and the scripts
   reject a different revision.
2. Install the C++ build tools and Windows SDK described in the
   [official Odin installation guide](https://odin-lang.org/docs/install/).
3. Put `odin.exe` on PATH, or set `$env:ODIN = 'C:\ODIN\odin.exe'` in PowerShell.
   Alternatively pass `-OdinPath C:\ODIN\odin.exe` to either script.
4. Run:

   ```powershell
   .\test.ps1
   .\build.ps1
   .\run.bat
   .\build.ps1 release
   ```

`test.bat` and `build.bat` forward arguments to the PowerShell scripts. Scripts
resolve paths from their own location and can be invoked from another directory.
The batch wrappers use a process-local execution policy override.

The required clockwork core is included at `deps/clockwork-ecs/clockwork`. Its
exact version, origin, permission and hashes are documented in
[the snapshot README](../deps/clockwork-ecs/README.md). The scripts check every
source file against that manifest. There is no private sibling dependency.
Raylib and microui come from the pinned Odin archive. Clay's existing Windows
binding and static library remain in `clay/`.

The scripts select LLVM's **lld** linker. The default radlink shipped with this
Odin release crashed linking this game's debug build locally; lld links the same
source and resources successfully.

Build output: `bin/tormentas.exe`. Release output: `dist/tormentas/` and
`dist/tormentas-release.zip`. The default build and release have no Steam
dependency. Steam lobbies, invites, online play and the Steam-backed loopback
transport are unavailable. Single-player remains available. See
[STEAMWORKS.md](STEAMWORKS.md) for optional local Steam setup.

## Automated tests

`test.ps1` runs three suites and returns nonzero on any failure:

| Suite | Coverage |
| --- | --- |
| clockwork | Stable entity restoration, exact numeric reflection, range metadata, inspector tags and registry behavior |
| protocol | Input/entity round trips and every truncated length; editor queue draining; raid result truncation; snapshot completeness; disabled transport |
| game | Isometric round trips; equal screen speed in eight directions; pathfinding blockers, corner cutting and stationary goals |

Tests execute production Odin functions with memory tracking enabled. They need
no window, assets, Steam client, SDK, network or account. They run with one worker
because navigation uses global state. They do not validate rendering, audio, full
raids or live multiplayer.
