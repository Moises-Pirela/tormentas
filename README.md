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

**Prerequisites**

- Windows
- The [Odin compiler](https://odin-lang.org/docs/install/). `build.ps1` expects it at
  `C:\ODIN\odin.exe` — edit that line if yours lives elsewhere.
- The `clockwork-ecs` repo cloned as a **sibling** of this one (i.e. `../clockwork-ecs`), so the
  build can resolve the `cw=` collection.
- The Steamworks SDK (`steamworks/` + `steam_api.dll`) is vendored in the repo.

**Build**

```bat
build.bat            :: debug build (-o:none -debug -vet)
build.bat release    :: optimized build (-o:aggressive -subsystem:windows)
```

Output lands at `bin\tormentas.exe`. (`build.bat` just forwards to `build.ps1`.)

**Run**

```bat
run.bat
```

### Local co-op testing

Double-click `run.bat` in two separate windows. The first instance hosts (**Host Game**); the
second joins (**Join Game**, enter `127.0.0.1`).

## Layout

```
src/        Game and engine source (Odin)
data/       Content: levels, sprites, sounds, fonts, loc, config, loot tables
tools/      gen_level scripts and asset helpers
clay/       Clay UI bindings
steamworks/ Steamworks SDK bindings
bin/ dist/  Build output
```

## Conventions

Source files carry **no comments** — every design rationale that would have been a comment lives in
[`TUNING.md`](TUNING.md) instead. Read it before changing movement, projection, netcode, or combat
math.

## License

[MIT](LICENSE) © 2026 Moises Pirela. Note that bundled third-party components keep their own
licenses — notably the Steamworks SDK, which is not MIT-licensed.
