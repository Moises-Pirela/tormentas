# Las Tormentas

An isometric extraction-roguelite with co-op, built from scratch in [Odin](https://odin-lang.org/)
on a custom ECS and [raylib](https://www.raylib.com/). Drop into a storm-wracked frontier, fight
your way through a raid, and extract with your loot — or lose it.

> **Status:** in active development. The engine and systems are deep; content is still being
> filled in. Not yet feature-complete or balanced.

## Gameplay

The core loop is **raid → extract → hub → upgrade → raid again**:

- **Raids.** Hand-placed isometric levels full of enemies, traps, loot, and environmental
  interactables. Reach an extraction point and channel out to bank what you found.
- **The hub.** Between raids, spend your haul at the shop, stash gear, buy abilities, grow your
  mutation tree, and take quests.
- **Buildcraft.** Four character classes, each locked to a single weapon archetype that matches
  its sprite. A deep mutation tree, an ability roster, and a wide affix/rarity system on gear give
  runs a lot of build variety.
- **Co-op.** Two-player online play over a deterministic lockstep model, with Steam friend invites.

## Tech

Everything here is hand-rolled — no commercial engine.

- **Language:** Odin
- **Rendering / platform:** raylib (via Odin's `vendor:raylib`)
- **ECS:** `clockwork` — a separate package (`clockwork-ecs`), wired in as a `cw` collection
- **UI:** Clay (immediate-mode layout) with render-texture-cached panels
- **Netcode:** fixed 60 Hz timestep, lockstep P2P determinism (only inputs cross the wire), Steamworks for lobbies/invites
- **Localization:** English, Spanish, Portuguese (`data/loc.csv`)
- **In-house tools:** a level editor, an animation-sheet editor, and a dev console, all built into the game

## Building

Windows x64 and **Odin dev-2026-10 (84bc3fc)** are required. Download the complete
toolchain from the [official release](https://github.com/odin-lang/Odin/releases/tag/dev-2026-10)
and put `odin.exe` on PATH or set `ODIN` to its full path. See
[SETUP.md](docs/SETUP.md) for Windows build tools and exact setup instructions.

The required MIT-licensed clockwork snapshot is included in
[`deps/clockwork-ecs`](deps/clockwork-ecs/README.md), with provenance and a verified
SHA-256 manifest. No sibling repository or private download is needed.

The default build supports single-player without Steam. Steamworks SDK material
is excluded from submitted source; optional local Steam setup and sharing-rights
details are in [STEAMWORKS.md](docs/STEAMWORKS.md).

**Build**

```bat
test.bat             :: automated clockwork, protocol and game logic tests
build.bat            :: debug build (-o:none -debug -vet, LLVM lld)
build.bat release    :: optimized build (-o:aggressive -subsystem:windows)
```

Output lands at `bin\tormentas.exe`. (`build.bat` just forwards to `build.ps1`.)

**Run**

```bat
run.bat
```

### Optional co-op testing

Steam and loopback multiplayer require the optional Steam build described in
[STEAMWORKS.md](docs/STEAMWORKS.md). They are disabled in the default submission build.

### Training submission

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/export-source.ps1`
and submit `dist/tormentas-source.zip`. It includes current fixes, tests and pinned
clockwork source, and excludes private SDK copies and Git history. Historical
commits still contain the previously bundled Steamworks material.

## Layout

```
src/        Game and engine source (Odin)
data/       Content: levels, sprites, sounds, fonts, loc, config, loot tables
tools/      gen_level scripts and asset helpers
clay/       Clay UI bindings
deps/       Pinned clockwork core and disabled Steam package
ui/         Project-owned microui adapters
docs/       Reproducible setup and Steamworks submission notes
bin/ dist/  Build output
```

## Conventions

Source files carry **no comments** — every design rationale that would have been a comment lives in
[`TUNING.md`](TUNING.md) instead. Read it before changing movement, projection, netcode, or combat
math.

## License

[MIT](LICENSE) © 2026 Moises Pirela, including the clockwork snapshot included with
the owner's authorization. Existing third-party components retain their own rights;
the MIT license does not cover separately obtained Steamworks SDK material.
