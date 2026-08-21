package main

import "core:math"
import rl "vendor:raylib"

ISO_TILE_W :: f32(TILE_SIZE)
ISO_TILE_H :: f32(TILE_SIZE) * 0.5

world_to_iso_xy :: proc(wx, wy: f32) -> rl.Vector2 {
    return {
        (wx - wy),
        (wx + wy) * 0.5,
    }
}

world_to_iso_v :: proc(pos: rl.Vector2) -> rl.Vector2 {
    return world_to_iso_xy(pos.x, pos.y)
}

iso_to_world_xy :: proc(ix, iy: f32) -> rl.Vector2 {
    return {
        iy + ix * 0.5,
        iy - ix * 0.5,
    }
}

screen_to_world_cartesian :: proc(screen: rl.Vector2) -> rl.Vector2 {
    iso := rl.GetScreenToWorld2D(screen, g_camera^)
    return iso_to_world_xy(iso.x, iso.y)
}

camera_set_target_world :: proc(wx, wy: f32) {
    iso := world_to_iso_xy(wx, wy)
    lims := g_level_data.cam_lims

    if lims[1] > lims[0] {
        half_w := (f32(rl.GetScreenWidth()) * 0.5) / g_camera.zoom
        lo, hi := lims[0] + half_w, lims[1] - half_w
        iso.x = clamp(iso.x, lo, hi) if lo <= hi else (lims[0] + lims[1]) * 0.5
    }
    if lims[3] > lims[2] {
        half_h := (f32(rl.GetScreenHeight()) * 0.5) / g_camera.zoom
        lo, hi := lims[2] + half_h, lims[3] - half_h
        iso.y = clamp(iso.y, lo, hi) if lo <= hi else (lims[2] + lims[3]) * 0.5
    }

    g_camera.target = iso
}

screen_dir_to_world_dir :: proc(dir: [2]f32) -> [2]f32 {
    wx := dir[1] + dir[0] * 0.5
    wy := dir[1] - dir[0] * 0.5
    if wx == 0 && wy == 0 { return {} }
    return { wx, wy }
}

world_rot_to_iso :: proc(angle: f32) -> f32 {
    c := math.cos(angle)
    s := math.sin(angle)
    return math.atan2((c + s) * 0.5, c - s)
}

iso_depth_sort_y :: proc(wx, wy: f32) -> f32 {
    return wx + wy
}

iso_tile_bounds :: proc(tx, ty: int) -> (center: rl.Vector2, top: rl.Vector2, right: rl.Vector2, bottom: rl.Vector2, left: rl.Vector2) {
    wx := f32(tx * TILE_SIZE)
    wy := f32(ty * TILE_SIZE)
    center = world_to_iso_xy(wx + f32(TILE_SIZE) * 0.5, wy + f32(TILE_SIZE) * 0.5)

    half_w := ISO_TILE_W
    half_h := ISO_TILE_H
    top    = { center.x,          center.y - half_h }
    right  = { center.x + half_w, center.y          }
    bottom = { center.x,          center.y + half_h }
    left   = { center.x - half_w, center.y          }
    return
}

cartesian_view_bounds :: proc(pad: f32 = 0) -> (min_x, min_y, max_x, max_y: f32) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    p0 := screen_to_world_cartesian({ -pad, -pad })
    p1 := screen_to_world_cartesian({ sw + pad, -pad })
    p2 := screen_to_world_cartesian({ -pad, sh + pad })
    p3 := screen_to_world_cartesian({ sw + pad, sh + pad })

    min_x = min(min(p0.x, p1.x), min(p2.x, p3.x))
    min_y = min(min(p0.y, p1.y), min(p2.y, p3.y))
    max_x = max(max(p0.x, p1.x), max(p2.x, p3.x))
    max_y = max(max(p0.y, p1.y), max(p2.y, p3.y))
    return
}

iso_draw_shadow_diamond :: proc(center: rl.Vector2, width, height: f32, color: rl.Color) {
    hw := width * 0.5
    hh := height * 0.5
    rl.DrawTriangle(
        { center.x, center.y - hh },
        { center.x + hw, center.y },
        { center.x, center.y + hh },
        color,
    )
    rl.DrawTriangle(
        { center.x, center.y - hh },
        { center.x, center.y + hh },
        { center.x - hw, center.y },
        color,
    )
}
