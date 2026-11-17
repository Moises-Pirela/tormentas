package main

// The camera, and the projection between world, view and screen space (docs/BUILD_PLAN.md, P1a
// step 5). This is the seam P1b swaps: a top-down perspective camera replaces the 2D isometric
// one, and "view space" stops being a 2D isometric plane and becomes the 3D world. Nothing
// outside this file touches the camera or the isometric maths.

import "core:math"
import gfx "gfx"

// The 2D camera the backend draws through. P1b replaces it with a 3D orbit camera.
@(private = "file") g_cam: gfx.Camera2D

cam_init :: proc() {
    g_cam = gfx.Camera2D{
        offset   = { SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0 },
        target   = { 0, 0 },
        rotation = 0,
        zoom     = CAMERA_ZOOM,
    }
}

// Draw through the camera until cam_end.
cam_begin :: proc() { gfx.camera_begin(g_cam) }
cam_end   :: proc() { gfx.camera_end() }

// --- camera state. View space is what the camera's target and offset are expressed in.
cam_zoom       :: proc() -> f32      { return g_cam.zoom }
cam_set_zoom   :: proc(z: f32)       { g_cam.zoom = z }
cam_target     :: proc() -> gfx.Vec2 { return g_cam.target }
cam_set_target_view :: proc(v: gfx.Vec2) { g_cam.target = v }
cam_pan_view   :: proc(d: gfx.Vec2)  { g_cam.target += d }
cam_offset     :: proc() -> gfx.Vec2 { return g_cam.offset }
cam_set_offset :: proc(v: gfx.Vec2)  { g_cam.offset = v }
cam_nudge_offset :: proc(d: gfx.Vec2) { g_cam.offset += d }

// --- view <-> screen, through the camera.
cam_view_to_screen :: proc(view: gfx.Vec2) -> gfx.Vec2   { return gfx.world_to_screen(view, g_cam) }
cam_screen_to_view :: proc(screen: gfx.Vec2) -> gfx.Vec2 { return gfx.screen_to_world(screen, g_cam) }

// --- world -> screen, the whole chain (what HUD overlays anchored to entities need).
cam_world_to_screen_xy :: proc(wx, wy: f32) -> gfx.Vec2 { return cam_view_to_screen(cam_world_to_view_xy(wx, wy)) }
cam_world_to_screen    :: proc(pos: gfx.Vec2) -> gfx.Vec2 { return cam_view_to_screen(cam_world_to_view(pos)) }

ISO_TILE_W :: f32(TILE_SIZE)
ISO_TILE_H :: f32(TILE_SIZE) * 0.5

cam_world_to_view_xy :: proc(wx, wy: f32) -> gfx.Vec2 {
    return {
        (wx - wy),
        (wx + wy) * 0.5,
    }
}

cam_world_to_view :: proc(pos: gfx.Vec2) -> gfx.Vec2 {
    return cam_world_to_view_xy(pos.x, pos.y)
}

cam_view_to_world_xy :: proc(ix, iy: f32) -> gfx.Vec2 {
    return {
        iy + ix * 0.5,
        iy - ix * 0.5,
    }
}

cam_screen_to_world :: proc(screen: gfx.Vec2) -> gfx.Vec2 {
    iso := cam_screen_to_view(screen)
    return cam_view_to_world_xy(iso.x, iso.y)
}

cam_set_target_world :: proc(wx, wy: f32) {
    iso := cam_world_to_view_xy(wx, wy)
    lims := g_level_data.cam_lims

    if lims[1] > lims[0] {
        half_w := (f32(gfx.screen_width()) * 0.5) / g_cam.zoom
        lo, hi := lims[0] + half_w, lims[1] - half_w
        iso.x = clamp(iso.x, lo, hi) if lo <= hi else (lims[0] + lims[1]) * 0.5
    }
    if lims[3] > lims[2] {
        half_h := (f32(gfx.screen_height()) * 0.5) / g_cam.zoom
        lo, hi := lims[2] + half_h, lims[3] - half_h
        iso.y = clamp(iso.y, lo, hi) if lo <= hi else (lims[2] + lims[3]) * 0.5
    }

    g_cam.target = iso
}

cam_dir_to_world :: proc(dir: [2]f32) -> [2]f32 {
    wx := dir[1] + dir[0] * 0.5
    wy := dir[1] - dir[0] * 0.5
    if wx == 0 && wy == 0 { return {} }
    return { wx, wy }
}

cam_world_rot_to_view :: proc(angle: f32) -> f32 {
    c := math.cos(angle)
    s := math.sin(angle)
    return math.atan2((c + s) * 0.5, c - s)
}

cam_depth_sort_y :: proc(wx, wy: f32) -> f32 {
    return wx + wy
}

cam_tile_bounds :: proc(tx, ty: int) -> (center: gfx.Vec2, top: gfx.Vec2, right: gfx.Vec2, bottom: gfx.Vec2, left: gfx.Vec2) {
    wx := f32(tx * TILE_SIZE)
    wy := f32(ty * TILE_SIZE)
    center = cam_world_to_view_xy(wx + f32(TILE_SIZE) * 0.5, wy + f32(TILE_SIZE) * 0.5)

    half_w := ISO_TILE_W
    half_h := ISO_TILE_H
    top    = { center.x,          center.y - half_h }
    right  = { center.x + half_w, center.y          }
    bottom = { center.x,          center.y + half_h }
    left   = { center.x - half_w, center.y          }
    return
}

cam_view_bounds :: proc(pad: f32 = 0) -> (min_x, min_y, max_x, max_y: f32) {
    sw := f32(gfx.screen_width())
    sh := f32(gfx.screen_height())
    p0 := cam_screen_to_world({ -pad, -pad })
    p1 := cam_screen_to_world({ sw + pad, -pad })
    p2 := cam_screen_to_world({ -pad, sh + pad })
    p3 := cam_screen_to_world({ sw + pad, sh + pad })

    min_x = min(min(p0.x, p1.x), min(p2.x, p3.x))
    min_y = min(min(p0.y, p1.y), min(p2.y, p3.y))
    max_x = max(max(p0.x, p1.x), max(p2.x, p3.x))
    max_y = max(max(p0.y, p1.y), max(p2.y, p3.y))
    return
}

cam_draw_shadow_diamond :: proc(center: gfx.Vec2, width, height: f32, color: gfx.Color) {
    hw := width * 0.5
    hh := height * 0.5
    gfx.draw_triangle(
        { center.x, center.y - hh },
        { center.x + hw, center.y },
        { center.x, center.y + hh },
        color,
    )
    gfx.draw_triangle(
        { center.x, center.y - hh },
        { center.x, center.y + hh },
        { center.x - hw, center.y },
        color,
    )
}
