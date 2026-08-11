# Architecture Notes

## Direction

The engine should treat semantic data as the source of truth. Geometry, collision,
nav data, encounter placement, props, lighting, and debug views are generated
outputs.

The practical rule is:

```text
semantic description -> generator pass -> generated runtime data -> rendering/gameplay
```

Avoid authoring meshes or scene objects directly when a compact semantic description
can produce them.

## Core Runtime Layers

1. Foundation

Deterministic IDs, fixed tick timing, simple allocators, logging, assertions,
profile scopes, random streams, and file watching.

2. Semantic Database

Declarative definitions for regions, districts, spaces, traversal links,
landmarks, factions, encounter intents, character archetypes, weapon recipes,
and generator rules.

3. Generator Graph

Small passes that consume semantic data and produce runtime artifacts. Each pass
should be independently inspectable and incrementally regeneratable.

4. Simulation

Player, AI, weapons, projectiles, animation state, procedural motion, triggers,
objectives, and encounter control. This should use a fixed tick and deterministic
state transitions wherever possible.

5. Presentation

Camera, procedural mesh draw data, material parameters, decals, particles, audio
events, and UI/debug overlays. Presentation can be more flexible, but simulation
truth should remain stable.

## Procedural Generation Contract

Every generator should expose:

- Inputs: semantic source, seed, version, and parameters.
- Outputs: generated data handles and counts.
- Trace: the high-level decisions it made.
- Invalidations: what can be regenerated without rebuilding the whole world.

The trace is important. A solo developer needs to ask "why did this happen?" and
get an answer without stepping through every generator.

## Authoring Rules

- Prefer JSON, CSV, or another plain declarative format while ideas are changing.
- Keep visual tools narrow: splines, portals, patrol paths, trigger volumes,
  landmark placement, and connectivity views are worth building.
- Do not build a general-purpose scene editor.
- Runtime inspection should be available before complex editing tools.
- Hot reload should preserve player position and simulation context when possible.

## First Systems To Prototype

- Region and combat-space semantic data.
- Deterministic generator traces.
- First-person controller with grounded movement and readable momentum.
- Hitscan/projectile weapon testbed.
- AI perception, cover choice, pressure, retreat, and flanking.
- Procedural body rig made from primitive parts.
- Procedural weapon rig made from modular parts.
- Debug overlays for nav, cover, line of sight, sound propagation, and encounters.

