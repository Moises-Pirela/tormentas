# Odin Guidelines

These guidelines come from the current `proj-tormentas` style, adjusted for the
new FPS project.

## Project Shape

- Keep code in a flat `src` package until there is real pressure to split packages.
- Use `package main` for the game executable.
- Add separate packages only for reusable foundations that clearly stand alone.
- Keep build scripts simple and local.
- Keep data under `data/`, not embedded in code.

## Coding Style

- Prefer plain structs, enums, and small procedures.
- Keep system procedures explicit: `ai_system`, `weapon_system`, `camera_system`,
  `generator_trace_system`, and similar.
- Use package globals sparingly for durable runtime services and app state.
- Keep constants near the systems that own them.
- Avoid inheritance-like abstractions. Compose data.
- Prefer fixed arrays when limits are deliberate and useful for determinism.
- Prefer dynamic arrays when authoring data can grow and iteration speed matters.

## Simulation

- Use a fixed tick for gameplay simulation.
- Separate staged input from simulation state.
- Keep random generation behind named deterministic streams.
- Treat generated data as rebuildable output.
- Keep rendering and debug drawing outside core simulation rules.

## Procedural Data

Semantic data should name intent, not geometry:

```json
{
  "kind": "combat_space",
  "intent": "mid_range_crossfire",
  "cover_density": 0.45,
  "verticality": 0.35,
  "exit_policy": "two_forward_one_backtrack"
}
```

Generators can then decide how this becomes columns, bridges, ramps, overlooks,
bulkheads, ducts, sightlines, cover, and encounter markers.

## Debugging

Every major system should have a cheap way to explain itself:

- AI: current goal, threat, cover score, route intent.
- Weapons: recoil state, spread, heat, reload phase, projectile source.
- Animation: active procedural layers, IK targets, spring state.
- World generation: source semantic object, generator seed, rule trace.
- Encounters: spawn budget, pressure state, retreat routes, objective gates.

