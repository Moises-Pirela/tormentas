package main

import    "core:fmt"
import    "core:math"
import im "../deps/imgui/imgui"
import rl "vendor:raylib"

EditorTool :: enum u8 {
    Select,
    Place,
    Paint,
    Erase,
}

GIZMO_HANDLE_LEN :: f32(78)
GIZMO_GRAB_R     :: f32(12)
GIZMO_AXIS_PICK  :: f32(8)
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
@(private = "file") g_gz_hover: GizmoAxis
@(private = "file") g_gz_grab:  [2]f32
@(private = "file") g_gz_start: [3]f32
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
    g_gz_axis  = .None
    g_gz_hover = .None
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

@(private = "file")
_seg_dist :: proc(p, a, b: rl.Vector2) -> f32 {
    ab := rl.Vector2{ b.x - a.x, b.y - a.y }
    l2 := ab.x*ab.x + ab.y*ab.y
    t  := f32(0)
    if l2 > 0 { t = clamp(((p.x - a.x)*ab.x + (p.y - a.y)*ab.y) / l2, 0, 1) }
    dx := p.x - (a.x + ab.x * t)
    dy := p.y - (a.y + ab.y * t)
    return math.sqrt(dx*dx + dy*dy)
}

@(private = "file")
_gizmo_hit :: proc(e: ^LevelEntity, mouse: rl.Vector2) -> GizmoAxis {
    origin := ed_gizmo_origin_screen(e)
    if _near(mouse, origin, GIZMO_GRAB_R) { return .Free }
    hx := gizmo_handle_screen(origin, {1, 0})
    hy := gizmo_handle_screen(origin, {0, 1})
    dx := _seg_dist(mouse, origin, hx)
    dy := _seg_dist(mouse, origin, hy)
    if min(dx, dy) > GIZMO_AXIS_PICK { return .None }
    return .WorldX if dx <= dy else .WorldY
}

ed_gizmo_snap_active :: proc() -> bool {
    return g_ed_snap != platform_cmd_down()
}

ed_gizmo_hover :: proc() -> GizmoAxis { return g_gz_hover }

ed_gizmo_update :: proc(mouse: rl.Vector2) {
    e := ed_entity_selected()
    if e == nil { g_gz_axis = .None; g_gz_hover = .None; return }

    if g_gz_axis == .None { g_gz_hover = _gizmo_hit(e, mouse) }

    if rl.IsMouseButtonPressed(.LEFT) && g_gz_hover != .None {
        world := screen_to_world_cartesian(mouse)
        g_gz_grab  = { e.position[0] - world.x, e.position[1] - world.y }
        g_gz_start = e.position
        g_gz_axis  = g_gz_hover
    }

    if g_gz_axis != .None || g_gz_hover != .None { im.SetMouseCursor(.ResizeAll) }

    if rl.IsMouseButtonReleased(.LEFT) && g_gz_axis != .None {
        g_gz_axis = .None
        if e.position != g_gz_start { ed_entity_respawn_world() }
        return
    }

    if g_gz_axis == .None || !rl.IsMouseButtonDown(.LEFT) { return }

    world := screen_to_world_cartesian(mouse)
    want  := [2]f32{ world.x + g_gz_grab[0], world.y + g_gz_grab[1] }

    if ed_gizmo_snap_active() {
        want[0] = math.round(want[0] / f32(TILE_SIZE)) * f32(TILE_SIZE)
        want[1] = math.round(want[1] / f32(TILE_SIZE)) * f32(TILE_SIZE)
    }

    #partial switch g_gz_axis {
    case .WorldX: e.position[0] = want[0]; e.position[1] = g_gz_start[1]
    case .WorldY: e.position[1] = want[1]; e.position[0] = g_gz_start[0]
    case .Free:   e.position[0] = want[0]; e.position[1] = want[1]
    }
    _gizmo_sync_live(e)
}

@(private = "file")
_gizmo_sync_live :: proc(e: ^LevelEntity) {
    if !g_sim_alive { return }
    if !world_is_valid(&g_sim.world, e.live_id) { return }
    if !world_has_component(&g_sim.world, e.live_id, .Transform) { return }
    comp_get(&g_sim.world, e.live_id, .Transform, TransformComp).position = e.position
}

ed_gizmo_cancel :: proc() {
    e := ed_entity_selected()
    if e != nil && g_gz_axis != .None {
        e.position = g_gz_start
        _gizmo_sync_live(e)
    }
    g_gz_axis = .None
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

@(private = "file")
_v :: proc(p: rl.Vector2) -> im.Vec2 { return { p.x, p.y } }

@(private = "file")
_gizmo_axis :: proc(dl: ^im.DrawList, origin, tip: rl.Vector2, col: u32, hot: bool, label: cstring) {
    thick := f32(4.5) if hot else f32(3)
    dir   := rl.Vector2{ tip.x - origin.x, tip.y - origin.y }
    l     := math.sqrt(dir.x*dir.x + dir.y*dir.y)
    if l < 0.001 { return }
    dir    = { dir.x / l, dir.y / l }
    perp  := rl.Vector2{ -dir.y, dir.x }
    start := rl.Vector2{ origin.x + dir.x * 10, origin.y + dir.y * 10 }
    head  := f32(13) if hot else f32(11)
    base  := rl.Vector2{ tip.x - dir.x * head, tip.y - dir.y * head }
    im.DrawList_AddLine(dl, _v(start), _v(base), 0xa0_00_00_00, thick + 2.5)
    im.DrawList_AddLine(dl, _v(start), _v(base), col, thick)
    w := head * 0.55
    a := rl.Vector2{ base.x + perp.x * w, base.y + perp.y * w }
    b := rl.Vector2{ base.x - perp.x * w, base.y - perp.y * w }
    im.DrawList_AddTriangleFilled(dl, _v(tip), _v(a), _v(b), col)
    im.DrawList_AddText(dl, { tip.x + dir.x * 6 - 4, tip.y + dir.y * 6 - 8 }, col, label)
}

ed_gizmo_draw :: proc(dl: ^im.DrawList) {
    e := ed_entity_selected()
    if e == nil { return }

    origin := ed_gizmo_origin_screen(e)
    hx     := gizmo_handle_screen(origin, {1, 0})
    hy     := gizmo_handle_screen(origin, {0, 1})
    active := g_gz_axis if g_gz_axis != .None else g_gz_hover

    if g_gz_axis != .None {
        h := f32(TILE_SIZE) * 0.5
        s := g_gz_start
        ghost := [4]im.Vec2{
            ed_world_to_screen(s[0] - h, s[1] - h), ed_world_to_screen(s[0] + h, s[1] - h),
            ed_world_to_screen(s[0] + h, s[1] + h), ed_world_to_screen(s[0] - h, s[1] + h),
        }
        for i in 0..<4 { im.DrawList_AddLine(dl, ghost[i], ghost[(i + 1) % 4], 0x90_ff_ff_ff, 1.5) }
        sp := ed_world_to_screen(s[0], s[1])
        im.DrawList_AddLine(dl, sp, _v(origin), 0xb0_ff_ff_ff, 1.5)
        im.DrawList_AddCircleFilled(dl, sp, 3, 0xc0_ff_ff_ff)
    }

    _gizmo_axis(dl, origin, hx, 0xff_70_70_f0 if active == .WorldX else 0xff_50_5a_e1, active == .WorldX, "X")
    _gizmo_axis(dl, origin, hy, 0xff_ff_d0_80 if active == .WorldY else 0xff_eb_aa_5a, active == .WorldY, "Y")

    free_hot := active == .Free
    im.DrawList_AddCircleFilled(dl, _v(origin), 7 if free_hot else 5, 0xff_78_dc_ff if free_hot else 0xf0_f0_f0_f0)
    im.DrawList_AddCircle(dl, _v(origin), GIZMO_GRAB_R, 0xd0_78_dc_ff if free_hot else 0x80_f0_f0_f0, 32, 2 if free_hot else 1.5)

    if g_gz_axis == .None {
        ed_screen_label(dl, { origin.x + 16, origin.y - 40 },
            fmt.ctprintf("%s   %.0f, %.0f", e.def, e.position[0], e.position[1]), rl.Color{ 235, 235, 210, 255 })
    } else {
        dx := e.position[0] - g_gz_start[0]
        dy := e.position[1] - g_gz_start[1]
        snap := fmt.ctprintf("snap %d", TILE_SIZE) if ed_gizmo_snap_active() else cstring("free")
        ed_screen_label(dl, { origin.x + 16, origin.y - 40 },
            fmt.ctprintf("%+.0f, %+.0f   %s   Esc cancels", dx, dy, snap), rl.Color{ 255, 220, 120, 255 })
    }
}

ed_gizmo_probe_drag :: proc(dx, dy: f32) {
    e := ed_entity_selected()
    if e == nil { return }
    g_gz_start  = e.position
    g_gz_axis   = .Free
    e.position[0] += dx
    e.position[1] += dy
    _gizmo_sync_live(e)
}

ed_gizmo_probe_handle :: proc() -> rl.Vector2 {
    e := ed_entity_selected()
    if e == nil { return {} }
    origin := ed_gizmo_origin_screen(e)
    hx := gizmo_handle_screen(origin, {1, 0})
    return { (origin.x + hx.x) * 0.5, (origin.y + hx.y) * 0.5 }
}
