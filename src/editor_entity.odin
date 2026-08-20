package main

import "core:math"
import "core:strings"
import rl "vendor:raylib"

EditorTool :: enum u8 {
    Select,
    Place,
    Paint,
    Erase,
}

GIZMO_HANDLE_LEN :: f32(78)
GIZMO_GRAB_R     :: f32(11)
ENTITY_PICK_R    :: f32(26)

GizmoAxis :: enum u8 {
    None,
    WorldX,
    WorldY,
    Free,
}

g_ed_tool:        EditorTool = .Select
g_ed_def_idx:     int
g_ed_sel_entity:  int = -1
g_ed_snap:        bool = true

@(private = "file") g_gz_axis:  GizmoAxis
@(private = "file") g_gz_grab:  [2]f32
@(private = "file") g_ed_base:  [dynamic]FieldOverride

ed_entity_snapshot :: proc() {
    if !g_sim_alive { return }
    e := ed_entity_selected()
    if e == nil { level_entity_snapshot(&g_sim.world, INVALID_ENTITY, &g_ed_base); return }
    level_entity_snapshot(&g_sim.world, e.live_id, &g_ed_base)
}

ed_entity_capture :: proc() {
    if !g_sim_alive { return }
    level_entity_capture(&g_sim.world, g_ed_sel_entity, g_ed_base[:])
}

ed_entity_selected :: proc() -> ^LevelEntity {
    if g_ed_sel_entity < 0 || g_ed_sel_entity >= len(g_level_data.entities) { return nil }
    return &g_level_data.entities[g_ed_sel_entity]
}

ed_entity_deselect :: proc() {
    g_ed_sel_entity = -1
    g_gz_axis = .None
}

ed_entity_validate :: proc() {
    if g_ed_sel_entity >= len(g_level_data.entities) { ed_entity_deselect() }
}

ed_entity_pick :: proc(screen: rl.Vector2) -> int {
    best     := -1
    best_d2  := ENTITY_PICK_R * ENTITY_PICK_R

    for &e, i in g_level_data.entities {
        iso := world_to_iso_xy(e.position[0], e.position[1])
        p   := rl.GetWorldToScreen2D({iso.x, iso.y}, g_camera^)
        dx  := p.x - screen.x
        dy  := p.y - screen.y
        d2  := dx*dx + dy*dy
        if d2 <= best_d2 {
            best_d2 = d2
            best    = i
        }
    }
    return best
}

ed_entity_place :: proc(world: rl.Vector2) {
    if len(g_entity_defs) == 0 { return }
    ed_entity_capture()
    idx := clamp(g_ed_def_idx, 0, len(g_entity_defs) - 1)

    pos := [3]f32{ world.x, world.y, 0 }
    if g_ed_snap {
        pos[0] = math.round(world.x / f32(TILE_SIZE)) * f32(TILE_SIZE)
        pos[1] = math.round(world.y / f32(TILE_SIZE)) * f32(TILE_SIZE)
    }

    g_ed_sel_entity = level_entity_add(g_entity_defs[idx].name, pos)
    ed_entity_respawn_world()
    ed_entity_snapshot()
}

ed_entity_delete_selected :: proc() {
    if g_ed_sel_entity < 0 { return }
    level_entity_remove(g_ed_sel_entity)
    ed_entity_deselect()
    ed_entity_respawn_world()
}

ed_entity_respawn_world :: proc() {
    if !g_sim_alive { return }
    w := &g_sim.world

    ed_entity_capture()
    fire_system_reset()
    level_clear(w)
    director_init()
    level_apply(w)
    door_init_blockers(w)
    if g_hub_active { hub_apply(w) }
    spawn_players(w)
}

@(private = "file")
gizmo_handle_screen :: proc(origin: rl.Vector2, axis: [2]f32) -> rl.Vector2 {
    iso := world_to_iso_xy(axis[0], axis[1])
    d   := rl.Vector2{iso.x, iso.y}
    l   := math.sqrt(d.x*d.x + d.y*d.y)
    if l <= 0.0001 { return origin }
    return { origin.x + d.x / l * GIZMO_HANDLE_LEN, origin.y + d.y / l * GIZMO_HANDLE_LEN }
}

ed_gizmo_origin_screen :: proc(e: ^LevelEntity) -> rl.Vector2 {
    iso := world_to_iso_xy(e.position[0], e.position[1])
    return rl.GetWorldToScreen2D({iso.x, iso.y}, g_camera^)
}

ed_gizmo_update :: proc(mouse: rl.Vector2) {
    e := ed_entity_selected()
    if e == nil { g_gz_axis = .None; return }

    origin := ed_gizmo_origin_screen(e)

    if rl.IsMouseButtonPressed(.LEFT) {
        hx := gizmo_handle_screen(origin, {1, 0})
        hy := gizmo_handle_screen(origin, {0, 1})

        world := screen_to_world_cartesian(mouse)
        g_gz_grab = { e.position[0] - world.x, e.position[1] - world.y }

        switch {
        case _near(mouse, hx, GIZMO_GRAB_R):     g_gz_axis = .WorldX
        case _near(mouse, hy, GIZMO_GRAB_R):     g_gz_axis = .WorldY
        case _near(mouse, origin, GIZMO_GRAB_R): g_gz_axis = .Free
        case:                                    g_gz_axis = .None
        }
    }

    if rl.IsMouseButtonReleased(.LEFT) && g_gz_axis != .None {
        g_gz_axis = .None
        ed_entity_respawn_world()
        return
    }

    if g_gz_axis == .None || !rl.IsMouseButtonDown(.LEFT) { return }

    world := screen_to_world_cartesian(mouse)
    want  := [2]f32{ world.x + g_gz_grab[0], world.y + g_gz_grab[1] }

    if g_ed_snap {
        want[0] = math.round(want[0] / f32(TILE_SIZE)) * f32(TILE_SIZE)
        want[1] = math.round(want[1] / f32(TILE_SIZE)) * f32(TILE_SIZE)
    }

    #partial switch g_gz_axis {
    case .WorldX: e.position[0] = want[0]
    case .WorldY: e.position[1] = want[1]
    case .Free:   e.position[0] = want[0]; e.position[1] = want[1]
    }

    if !g_sim_alive { return }
    if !world_is_valid(&g_sim.world, e.live_id) { return }
    if !world_has_component(&g_sim.world, e.live_id, .Transform) { return }
    comp_get(&g_sim.world, e.live_id, .Transform, TransformComp).position = e.position
}

ed_gizmo_dragging :: proc() -> bool {
    return g_gz_axis != .None
}

@(private = "file")
_near :: proc(a, b: rl.Vector2, r: f32) -> bool {
    dx := a.x - b.x
    dy := a.y - b.y
    return dx*dx + dy*dy <= r*r
}

ed_gizmo_draw :: proc() {
    e := ed_entity_selected()
    if e == nil { return }

    origin := ed_gizmo_origin_screen(e)
    hx     := gizmo_handle_screen(origin, {1, 0})
    hy     := gizmo_handle_screen(origin, {0, 1})

    col_x := rl.Color{225, 90, 80, 255}
    col_y := rl.Color{90, 170, 235, 255}
    if g_gz_axis == .WorldX { col_x = rl.Color{255, 220, 120, 255} }
    if g_gz_axis == .WorldY { col_y = rl.Color{255, 220, 120, 255} }

    rl.DrawLineEx(origin, hx, 2.5, col_x)
    rl.DrawLineEx(origin, hy, 2.5, col_y)
    rl.DrawCircleV(hx, 5, col_x)
    rl.DrawCircleV(hy, 5, col_y)
    rl.DrawCircleV(origin, 4, rl.Color{240, 240, 240, 230})
    rl.DrawCircleLinesV(origin, GIZMO_GRAB_R, rl.Color{240, 240, 240, 120})

    rl.DrawText(strings.clone_to_cstring(e.def, context.temp_allocator),
        i32(origin.x) + 14, i32(origin.y) - 30, 14, rl.Color{235, 235, 210, 220})
}
