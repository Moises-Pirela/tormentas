# Megastructure FPS

This directory is a seed for a new Odin project based on the current `proj-tormentas`
code style, but aimed at a first-person, procedural, single-player FPS.

The goal is not to fork all of `proj-tormentas`. The goal is to carry forward its
best working habits:

- Small Odin files grouped by system.
- Plain data as the source of content.
- Deterministic fixed-step simulation.
- Simple build scripts.
- Runtime inspection and debug visibility.
- Tools that solve concrete authoring problems instead of becoming a full editor.

## First Milestone

Build a tiny semantic prototype before rendering a full world:

1. Load or construct semantic region data.
2. Generate deterministic structural descriptions from that data.
3. Print generator traces that explain what rules fired.
4. Add hot reload once the data shape stabilizes.
5. Only then turn generated structures into meshes, collision, nav, encounters, and
   debug overlays.

## Layout

- `src/` contains a minimal Odin scaffold.
- `data/regions/` contains declarative content examples.
- `docs/` captures architectural rules and Odin conventions for this project.
- `build.ps1` mirrors the simple local build style used by `proj-tormentas`.

## Build

From this directory:

```powershell
.\build.ps1
```

Or from the repository root:

```powershell
.\megastructure_fps\build.ps1
```

