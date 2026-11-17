// Package gfx is the game's rendering, window and input API (docs/BUILD_PLAN.md P1a,
// docs/BACKEND_SWAP_PLAN.md). Game code names these types and calls these procedures; only this
// package knows which backend draws them.
//
// The types are the game's own: nothing here exposes a backend's conventions. In particular a
// Texture that comes from a render target carries `flipped`, and the backend decides what that
// means when sampling, so game code always uses positive, top-left source rectangles.
package gfx

// 2D vector in pixels or world units.
Vec2 :: [2]f32

// 8-bit RGBA, straight (non-premultiplied) alpha. Fields .r .g .b .a via array swizzle.
Color :: distinct [4]u8

// Axis-aligned rectangle: top-left corner plus size. Sizes are positive.
Rect :: struct {
    x, y, width, height: f32,
}

// 2D camera: `target` (the view-space point under `offset`), `offset` (its screen position),
// rotation in degrees, and zoom. P1b replaces the implementation behind src/camera.odin.
Camera2D :: struct {
    offset:   Vec2,
    target:   Vec2,
    rotation: f32,
    zoom:     f32,
}

TextureFilter :: enum u8 {
    Point,     // nearest; the default, as raylib had it
    Bilinear,
    Trilinear, // bilinear + mipmaps where the backend has them
}

TextureWrap :: enum u8 {
    Repeat,    // the default
    Clamp,
}

BlendMode :: enum u8 {
    Alpha,     // src.a, 1-src.a for colour and alpha alike
    Additive,  // src.a, 1
}

// A GPU texture. `id` is non-zero when valid; game code uses that as its validity check.
// `flipped` marks a texture whose backend storage runs bottom-up (raylib render targets).
Texture :: struct {
    id:      u32,
    width:   i32,
    height:  i32,
    flipped: bool,
    _h:      Backend_Texture,
}

// An offscreen target plus the texture it renders into.
RenderTexture :: struct {
    id:      u32,
    texture: Texture,
    _h:      Backend_Render_Texture,
}

// A font at a base size. Text is drawn at whatever size the caller asks for.
Font :: struct {
    id:   u32,
    size: f32,
    _h:   Backend_Font,
}

// CPU-side pixels, always 8-bit RGBA, tightly packed, top row first.
Image :: struct {
    pixels: []u8,
    width:  i32,
    height: i32,
}

WHITE :: Color{ 255, 255, 255, 255 }
BLACK :: Color{ 0, 0, 0, 255 }
BLANK :: Color{ 0, 0, 0, 0 }

// Full source rectangle of a texture, in its own pixels, top-left origin.
texture_src :: proc(t: Texture) -> Rect {
    return { 0, 0, f32(t.width), f32(t.height) }
}

// Full source rectangle of a render target's texture.
target_src :: proc(rt: RenderTexture) -> Rect {
    return texture_src(rt.texture)
}

// Texture coordinate for a point in a texture's pixels, honouring the backend's storage
// orientation. Use this when building UVs by hand instead of dividing by the size.
texture_uv :: proc(t: Texture, px, py: f32) -> Vec2 {
    u := px / f32(max(t.width, 1))
    v := py / f32(max(t.height, 1))
    if t.flipped { v = 1 - v }
    return { u, v }
}
