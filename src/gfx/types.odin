// Package gfx is the game's rendering API (docs/BUILD_PLAN.md, P1a). Game code names these
// types and, from step 4 on, calls these procedures; only this package talks to a backend.
//
// Step 2 (now): the types are *aliases* of raylib's, which still backs every draw call. That keeps
// the rename mechanical: a gfx.Color is an rl.Color, so the ~2,400 raylib calls that step 4
// rewrites need no casts in the meantime. Step 7 (sokol backend) turns these into the only
// definitions; nothing outside this package should depend on them being raylib's.
package gfx

import rl "vendor:raylib"

// 2D vector in pixels or world units. Plain [2]f32, as raylib's Vector2 already is.
Vec2 :: [2]f32

// 8-bit RGBA, straight (non-premultiplied) alpha. Fields .r .g .b .a via array swizzle.
Color :: rl.Color

// Axis-aligned rectangle: top-left corner plus size.
Rect :: rl.Rectangle

WHITE :: Color{ 255, 255, 255, 255 }
BLACK :: Color{ 0, 0, 0, 255 }
BLANK :: Color{ 0, 0, 0, 0 }
