package main

// =============================================================================
// LEVEL — binary level file: tiles, enemy spawns, exits, player start.
//
// Binary format  (little-endian, packed):
//   [4]u8  magic           "TRMT"
//   u16    version         1
//   u32    tile_count
//   tile_count   × { i16 x, i16 y, u8 type }        (5 bytes each)
//   u32    spawn_count
//   spawn_count  × { i16 x, i16 y, u8 enemy_type }  (5 bytes each)
//   u32    exit_count
//   exit_count   × { i16 x, i16 y, u16 target }     (6 bytes each)
//   f32    player_start_x
//   f32    player_start_y
//
// Lifecycle:
//   level_data_init / level_data_destroy  — allocate / free dynamic slices
//   level_load(n)                         — read file into g_tilemap + g_level_data
//   level_save(n)                         — write g_tilemap + g_level_data to file
//   level_apply(w)                        — spawn enemies from g_level_data
//   level_clear(w)                        — destroy ALL entities (players too)
//   spawn_players(w)                      — recreate player entities at player_start
//   level_do_switch(w, n)                 — clear + load(n) + apply + spawn_players
//
// Level switching:
//   level_exit_system (LateUpdate) sets g_pending_level_switch = target_level.
//   main.odin checks the flag AFTER sim_tick and calls level_do_switch.
// =============================================================================

import "core:os"
import "core:fmt"
import "core:math"
import cw  "clockwork"
import p2p "p2p"

LEVEL_DIR :: "data/levels"

// ─── Types ────────────────────────────────────────────────────────────────────

EnemySpawnType :: enum u8 {
    Melee  = 1,
    Brute  = 2,
    Hunter = 3,
    Ranged = 4,
    Sniper = 5,
}

SpawnPoint :: struct {
    tx, ty:     i16,
    enemy_type: EnemySpawnType,
}

LevelExit :: struct {
    tx, ty:       i16,
    target_level: u16,
}

LevelLight :: struct {
    tx, ty:    i16,
    r, g, b:   u8,
    radius:    f32,
    intensity: f32,
}

LevelNPC :: struct {
    tx, ty:   i16,
    npc_type: cw.NPCType,
}

LevelData :: struct {
    spawns:       [dynamic]SpawnPoint,
    exits:        [dynamic]LevelExit,
    lights:       [dynamic]LevelLight,
    npcs:         [dynamic]LevelNPC,
    player_start: [2]f32,
    lighting:     LevelLightingConfig,
}

// ─── Package-level globals ────────────────────────────────────────────────────

// g_entity_defs holds the loaded entity definitions (set in main, used by level_apply).
g_entity_defs: []EntityDef

// g_level_data is the authoritative runtime level data (spawns, exits, player start).
g_level_data: LevelData

// g_pending_level_switch is set by level_exit_system; main.odin acts on it after sim_tick.
// 0 = no pending switch; N = switch to level N.
g_pending_level_switch: u16

// ─── Raid timer ───────────────────────────────────────────────────────────────

RAID_TIME      :: f32(30 * 60)           // 30 minutes total per raid
EXTRACT_RADIUS :: f32(3 * TILE_SIZE)     // 3-tile proximity zone
EXTRACT_TIME   :: f32(30.0)              // seconds to stand in zone to extract

// g_raid_timer counts down from RAID_TIME to 0 during a raid.
// Zero = time is up = failed run.  Reset to 0 by enter_hub.
g_raid_timer: f32

// ─── Init / destroy ───────────────────────────────────────────────────────────

level_data_init :: proc() {
    g_level_data.spawns   = make([dynamic]SpawnPoint)
    g_level_data.exits    = make([dynamic]LevelExit)
    g_level_data.lights   = make([dynamic]LevelLight)
    g_level_data.npcs     = make([dynamic]LevelNPC)
    g_level_data.lighting = LIGHTING_CONFIG_DEFAULT
}

level_data_destroy :: proc() {
    delete(g_level_data.spawns)
    delete(g_level_data.exits)
    delete(g_level_data.lights)
    delete(g_level_data.npcs)
}

// ─── File path ────────────────────────────────────────────────────────────────

@(private = "file")
level_path :: proc(n: int) -> string {
    return fmt.tprintf("%s/level%02d.bin", LEVEL_DIR, n)
}

// ─── Binary I/O helpers ───────────────────────────────────────────────────────

@(private = "file")
lv_wb1 :: proc(buf: ^[dynamic]u8, v: u8)  { append(buf, v) }

@(private = "file")
lv_wb2 :: proc(buf: ^[dynamic]u8, v: u16) { append(buf, u8(v), u8(v >> 8)) }

@(private = "file")
lv_wb4 :: proc(buf: ^[dynamic]u8, v: u32) {
    append(buf, u8(v), u8(v>>8), u8(v>>16), u8(v>>24))
}

@(private = "file")
lv_wbi16 :: proc(buf: ^[dynamic]u8, v: i16) { lv_wb2(buf, cast(u16)v) }

@(private = "file")
lv_wbf32 :: proc(buf: ^[dynamic]u8, v: f32) { lv_wb4(buf, transmute(u32)v) }

@(private = "file")
lv_rb1 :: proc(raw: []u8, cur: int) -> (val: u8, next: int, ok: bool) {
    if cur >= len(raw) { return 0, cur, false }
    return raw[cur], cur + 1, true
}

@(private = "file")
lv_rb2 :: proc(raw: []u8, cur: int) -> (val: u16, next: int, ok: bool) {
    if cur + 2 > len(raw) { return 0, cur, false }
    return u16(raw[cur]) | u16(raw[cur+1])<<8, cur + 2, true
}

@(private = "file")
lv_rb4 :: proc(raw: []u8, cur: int) -> (val: u32, next: int, ok: bool) {
    if cur + 4 > len(raw) { return 0, cur, false }
    v := u32(raw[cur]) | u32(raw[cur+1])<<8 | u32(raw[cur+2])<<16 | u32(raw[cur+3])<<24
    return v, cur + 4, true
}

@(private = "file")
lv_rbi16 :: proc(raw: []u8, cur: int) -> (val: i16, next: int, ok: bool) {
    v, c, o := lv_rb2(raw, cur)
    return cast(i16)v, c, o
}

@(private = "file")
lv_rbf32 :: proc(raw: []u8, cur: int) -> (val: f32, next: int, ok: bool) {
    v, c, o := lv_rb4(raw, cur)
    return transmute(f32)v, c, o
}

// ─── Persistence ─────────────────────────────────────────────────────────────

LEVEL_MAGIC   :: [4]u8{'T', 'R', 'M', 'T'}
LEVEL_VERSION :: u16(4)

// level_save writes g_tilemap and g_level_data to data/levels/levelNN.bin.
level_save :: proc(n: int) {
    os.make_directory(LEVEL_DIR)

    buf := make([dynamic]u8, 0, 4096, context.temp_allocator)

    // Header
    append(&buf, LEVEL_MAGIC[0], LEVEL_MAGIC[1], LEVEL_MAGIC[2], LEVEL_MAGIC[3])
    lv_wb2(&buf, LEVEL_VERSION)

    // Tiles
    lv_wb4(&buf, u32(len(g_tilemap)))
    for k, v in g_tilemap {
        lv_wbi16(&buf, i16(k[0]))
        lv_wbi16(&buf, i16(k[1]))
        lv_wb1 (&buf, u8(v))
    }

    // Spawn points
    lv_wb4(&buf, u32(len(g_level_data.spawns)))
    for sp in g_level_data.spawns {
        lv_wbi16(&buf, sp.tx)
        lv_wbi16(&buf, sp.ty)
        lv_wb1 (&buf, u8(sp.enemy_type))
    }

    // Exits
    lv_wb4(&buf, u32(len(g_level_data.exits)))
    for ex in g_level_data.exits {
        lv_wbi16(&buf, ex.tx)
        lv_wbi16(&buf, ex.ty)
        lv_wb2 (&buf, ex.target_level)
    }

    // Player start
    lv_wbf32(&buf, g_level_data.player_start[0])
    lv_wbf32(&buf, g_level_data.player_start[1])

    // Authored NPCs (v4+)
    lv_wb4(&buf, u32(len(g_level_data.npcs)))
    for npc in g_level_data.npcs {
        lv_wbi16(&buf, npc.tx)
        lv_wbi16(&buf, npc.ty)
        lv_wb1 (&buf, u8(npc.npc_type))
    }

    // Point lights (v2+)
    lv_wb4(&buf, u32(len(g_level_data.lights)))
    for lt in g_level_data.lights {
        lv_wbi16(&buf, lt.tx)
        lv_wbi16(&buf, lt.ty)
        lv_wb1 (&buf, lt.r)
        lv_wb1 (&buf, lt.g)
        lv_wb1 (&buf, lt.b)
        lv_wbf32(&buf, lt.radius)
        lv_wbf32(&buf, lt.intensity)
    }

    // Lighting config (v3+)
    cfg := lighting_config_capture()
    lv_wbf32(&buf, cfg.sun_dir_x)
    lv_wbf32(&buf, cfg.sun_dir_y)
    lv_wbf32(&buf, cfg.cloud_freq)
    lv_wbf32(&buf, cfg.cloud_freq_fine)
    lv_wbf32(&buf, cfg.cloud_drift_x)
    lv_wbf32(&buf, cfg.cloud_drift_y)
    lv_wbf32(&buf, cfg.cloud_cell)
    lv_wbf32(&buf, cfg.cloud_thresh_lo)
    lv_wbf32(&buf, cfg.cloud_thresh_hi)
    lv_wbf32(&buf, cfg.cloud_alpha_min)
    lv_wbf32(&buf, cfg.cloud_alpha_max)
    lv_wbf32(&buf, cfg.cloud_contrast)
    lv_wbf32(&buf, cfg.cloud_tint_r)
    lv_wbf32(&buf, cfg.cloud_tint_g)
    lv_wbf32(&buf, cfg.cloud_tint_b)
    lv_wbf32(&buf, cfg.god_ray_spacing)
    lv_wbf32(&buf, cfg.god_ray_width)
    lv_wbf32(&buf, cfg.god_ray_thresh)
    lv_wbf32(&buf, cfg.god_ray_alpha)
    lv_wbf32(&buf, cfg.sun_intensity)
    lv_wbf32(&buf, cfg.ambient)
    lv_wbf32(&buf, cfg.shadow_alpha)
    lv_wbf32(&buf, cfg.sun_color_r)
    lv_wbf32(&buf, cfg.sun_color_g)
    lv_wbf32(&buf, cfg.sun_color_b)
    lv_wbf32(&buf, cfg.sprite_min_brightness)
    lv_wbf32(&buf, cfg.sprite_outline)
    lv_wbf32(&buf, cfg.sprite_diffuse)
    lv_wbf32(&buf, cfg.sprite_rim)
    lv_wbf32(&buf, cfg.sprite_shadow_response)
    lv_wbf32(&buf, cfg.fog_color_r)
    lv_wbf32(&buf, cfg.fog_color_g)
    lv_wbf32(&buf, cfg.fog_color_b)
    lv_wbf32(&buf, cfg.fog_density)
    lv_wbf32(&buf, cfg.fog_scatter)

    os.write_entire_file(level_path(n), buf[:])
}

// level_load reads data/levels/levelNN.bin into g_tilemap and g_level_data.
// Silently does nothing if the file is missing or has an unrecognised format.
level_load :: proc(n: int) {
    g_level_data.lighting = LIGHTING_CONFIG_DEFAULT
    defer lighting_config_apply(g_level_data.lighting)

    raw, ok := os.read_entire_file(level_path(n), context.temp_allocator)
    if !ok || len(raw) < 10 {
        // No file yet — give the designer a default canvas to work from
        tilemap_fill_default()
        clear(&g_level_data.spawns)
        clear(&g_level_data.exits)
        clear(&g_level_data.lights)
        clear(&g_level_data.npcs)
        g_level_data.player_start = {}
        return
    }

    cur := 0

    // Magic
    if raw[0] != 'T' || raw[1] != 'R' || raw[2] != 'M' || raw[3] != 'T' {
        clear(&g_level_data.spawns)
        clear(&g_level_data.exits)
        clear(&g_level_data.lights)
        clear(&g_level_data.npcs)
        g_level_data.player_start = {}
        return
    }
    cur = 4

    // Version — accept 1 (no lights), 2 (with lights), 3 (+ lighting config)
    ver, ver_c, ver_ok := lv_rb2(raw, cur)
    if !ver_ok || (ver != 1 && ver != 2 && ver != 3 && ver != 4) {
        clear(&g_level_data.spawns)
        clear(&g_level_data.exits)
        clear(&g_level_data.lights)
        clear(&g_level_data.npcs)
        g_level_data.player_start = {}
        return
    }
    cur = ver_c

    // Tiles
    clear(&g_tilemap)
    tc, tc_c, tc_ok := lv_rb4(raw, cur)
    if !tc_ok { return }
    cur = tc_c
    for _ in 0..<tc {
        x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
        y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
        t,  tc2, tok  := lv_rb1  (raw, cur);  if !tok  { return };  cur = tc2
        tt := clamp(int(t), int(TileType.Floor), int(TileType.Water))
        g_tilemap[[2]int{int(x), int(y)}] = TileType(tt)
    }

    // Spawn points
    clear(&g_level_data.spawns)
    sc, sc_c, sc_ok := lv_rb4(raw, cur)
    if !sc_ok { return }
    cur = sc_c
    for _ in 0..<sc {
        x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
        y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
        et, ec,  eok  := lv_rb1  (raw, cur);  if !eok  { return };  cur = ec
        append(&g_level_data.spawns, SpawnPoint{
            tx         = x,
            ty         = y,
            enemy_type = EnemySpawnType(clamp(int(et), 1, 5)),
        })
    }

    // Exits
    clear(&g_level_data.exits)
    exc, exc_c, exc_ok := lv_rb4(raw, cur)
    if !exc_ok { return }
    cur = exc_c
    for _ in 0..<exc {
        x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
        y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
        tl, tlc, tlok := lv_rb2  (raw, cur);  if !tlok { return };  cur = tlc
        append(&g_level_data.exits, LevelExit{tx = x, ty = y, target_level = tl})
    }

    // Player start
    px, pxc, pxok := lv_rbf32(raw, cur)
    if pxok {
        cur = pxc
        py, pyc, pyok := lv_rbf32(raw, cur)
        if pyok {
            g_level_data.player_start = {px, py}
            cur = pyc
        }
    }

    clear(&g_level_data.npcs)
    if ver >= 4 {
        nc, nc_c, nc_ok := lv_rb4(raw, cur)
        if nc_ok {
            cur = nc_c
            for _ in 0..<nc {
                nx, nxc, nxok := lv_rbi16(raw, cur); if !nxok { break }; cur = nxc
                ny, nyc, nyok := lv_rbi16(raw, cur); if !nyok { break }; cur = nyc
                nt, ntc, ntok := lv_rb1(raw, cur); if !ntok { break }; cur = ntc
                npc_type := cw.NPCType(clamp(int(nt), int(cw.NPCType.Shopkeeper), int(cw.NPCType.MutationWorkbench)))
                append(&g_level_data.npcs, LevelNPC{
                    tx = nx,
                    ty = ny,
                    npc_type = npc_type,
                })
            }
        }
    }

    // Point lights (v2+)
    clear(&g_level_data.lights)
    if ver >= 2 {
        lc, lc_c, lc_ok := lv_rb4(raw, cur)
        if lc_ok {
            cur = lc_c
            for _ in 0..<lc {
                lx,  lxc,  lxok  := lv_rbi16(raw, cur);  if !lxok  { break };  cur = lxc
                ly,  lyc,  lyok  := lv_rbi16(raw, cur);  if !lyok  { break };  cur = lyc
                lr,  lrc,  lrok  := lv_rb1  (raw, cur);  if !lrok  { break };  cur = lrc
                lg,  lgc,  lgok  := lv_rb1  (raw, cur);  if !lgok  { break };  cur = lgc
                lb,  lbc,  lbok  := lv_rb1  (raw, cur);  if !lbok  { break };  cur = lbc
                rad, radc, radok := lv_rbf32(raw, cur);  if !radok { break };  cur = radc
                int_, intc, intok := lv_rbf32(raw, cur);  if !intok { break };  cur = intc
                append(&g_level_data.lights, LevelLight{
                    tx = lx, ty = ly,
                    r = lr, g = lg, b = lb,
                    radius = rad, intensity = int_,
                })
            }
        }
    }

    // Lighting config (v3+)
    if ver >= 3 {
        lf :: proc(raw: []u8, cur: int, dst: ^f32) -> (next: int, ok: bool) {
            v, c, o := lv_rbf32(raw, cur)
            if o { dst^ = v }
            return c, o
        }
        c   := &g_level_data.lighting
        ok1  := true
        cur, ok1 = lf(raw, cur, &c.sun_dir_x);              if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sun_dir_y);              if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_freq);             if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_freq_fine);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_drift_x);          if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_drift_y);          if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_cell);             if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_thresh_lo);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_thresh_hi);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_alpha_min);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_alpha_max);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_contrast);         if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_tint_r);           if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_tint_g);           if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.cloud_tint_b);           if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.god_ray_spacing);        if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.god_ray_width);          if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.god_ray_thresh);         if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.god_ray_alpha);          if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sun_intensity);          if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.ambient);                if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.shadow_alpha);           if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sun_color_r);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sun_color_g);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sun_color_b);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sprite_min_brightness);  if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sprite_outline);         if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sprite_diffuse);         if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sprite_rim);             if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.sprite_shadow_response); if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.fog_color_r);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.fog_color_g);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.fog_color_b);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.fog_density);            if !ok1 { return }
        cur, ok1 = lf(raw, cur, &c.fog_scatter);            if !ok1 { return }
        _ = cur
    }

    g_wall_mask_dirty = true
}

level_apply :: proc(w: ^cw.World) {
    spawn_level_npc :: proc(w: ^cw.World, npc_type: cw.NPCType, wx, wy: f32) -> int {
        def_name := ""
        switch npc_type {
        case .Shopkeeper:
            def_name = "npc_shopkeeper"
        case .MutationWorkbench:
            def_name = "npc_mutation_workbench"
        }
        if def_name == "" { return cw.INVALID_ENTITY }

        id := spawn_from_def(w, find_entity_def(g_entity_defs, def_name))
        if id == cw.INVALID_ENTITY { return id }
        if cw.world_has_component(w, id, .Transform) {
            cw.world_get_transform(w, id).position = {wx, wy, 0}
        }
        switch npc_type {
        case .Shopkeeper:
            cw.world_set_wallet(w, id, cw.WalletComp{ gold = 200 })
            shop_roll_stock(w, id, 0)
        case .MutationWorkbench:
        }
        return id
    }

    for npc in g_level_data.npcs {
        wx := f32(int(npc.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(npc.ty) * TILE_SIZE + TILE_SIZE / 2)
        spawn_level_npc(w, npc.npc_type, wx, wy)
    }

    for sp in g_level_data.spawns {
        wx := f32(int(sp.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(sp.ty) * TILE_SIZE + TILE_SIZE / 2)

        spawn_enemy :: proc(w: ^cw.World, name: string, wx, wy: f32) -> int {
            id := spawn_from_def(w, find_entity_def(g_entity_defs, name))
            if id != cw.INVALID_ENTITY {
                cw.world_get_transform(w, id).position = {wx, wy, 0}
            }
            return id
        }

        switch sp.enemy_type {
        case .Melee:
            spawn_enemy(w, "enemy_melee",  wx, wy)
        case .Brute:
            spawn_enemy(w, "enemy_brute",  wx, wy)
        case .Hunter:
            spawn_enemy(w, "enemy_hunter", wx, wy)
        case .Ranged:
            wid := spawn_from_def(w, find_entity_def(g_entity_defs, "weapon_shotgun"))
            id  := spawn_enemy(w, "enemy_ranged", wx, wy)
            if id != cw.INVALID_ENTITY && wid != cw.INVALID_ENTITY {
                cw.world_set_equipment(w, id, cw.EquipmentComp{ weapon_entity_id = wid })
            }
        case .Sniper:
            wid := spawn_from_def(w, find_entity_def(g_entity_defs, "weapon_rifle"))
            id  := spawn_enemy(w, "enemy_sniper", wx, wy)
            if id != cw.INVALID_ENTITY && wid != cw.INVALID_ENTITY {
                cw.world_set_equipment(w, id, cw.EquipmentComp{ weapon_entity_id = wid })
            }
        }
    }

    for lt in g_level_data.lights {
        wx := f32(int(lt.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(lt.ty) * TILE_SIZE + TILE_SIZE / 2)
        id := cw.world_create_entity(w)
        cw.world_set_transform(w, id, cw.TransformComp{ position = {wx, wy, 0} })
        cw.world_set_point_light(w, id, cw.PointLightComp{
            color     = { f32(lt.r), f32(lt.g), f32(lt.b) },
            radius    = lt.radius,
            intensity = lt.intensity,
        })
    }
}

spawn_players :: proc(w: ^cw.World) {
    slots_to_spawn := 2 if p2p.session_is_online(&g_session) else 1
    ps             := g_level_data.player_start
    SLOT_OFFSET    :: f32(60)

    for slot in 0..<slots_to_spawn {
        sp: [3]f32
        if ps[0] != 0 || ps[1] != 0 {
            sp = { ps[0] + f32(slot) * SLOT_OFFSET, ps[1], 0 }
        } else {
            sp = { f32(slot) * SLOT_OFFSET, 0, 0 }
        }

        wep := spawn_from_def(w, find_entity_def(g_entity_defs, "weapon_pistol"))
        pid := spawn_from_def(w, find_entity_def(g_entity_defs, "player"))

        if cw.world_has_component(w, pid, .Transform) {
            cw.world_get_transform(w, pid).position = sp
        }
        cw.world_set_equipment(w, pid, cw.EquipmentComp{ weapon_entity_id = wep })
        cw.world_set_inventory(w, pid, cw.inventory_make_empty())
        cw.world_set_respawn(w, pid, cw.RespawnComp{ spawn_pos = sp, delay = RESPAWN_DELAY })
        cw.world_set_ability(w, pid, cw.AbilityComp{})
        cw.world_set_mutation(w, pid, cw.mutation_container_empty())
        cw.world_set_stats(w, pid, cw.StatsComp{
            strength    = 1,  dexterity  = 1, science    = 1,
            level       = 1,  xp         = 0, xp_next    = 100.0,
            stat_points = 0,  base_hp    = 100.0,
            base_energy = 100.0, base_speed = 150.0,
        })
        cw.world_set_player(w, pid, cw.PlayerComp{ slot = slot })
        cw.world_set_wallet(w, pid, cw.WalletComp{ gold = 0 })
        w.player_ids[slot] = pid
    }

    // Sync the local player shortcut; slot is fixed for the whole session.
    w.player_id = w.player_ids[w.local_player_slot]

    // Snap camera to spawn area.
    if ps[0] != 0 || ps[1] != 0 {
        g_camera.target = { ps[0], ps[1] }
    }
}

level_clear :: proc(w: ^cw.World) {
    g_pending_level_switch = 0

    _clear_all_shop_stock(w)

    ai_paths_clear()

    cw.world_reset(w)

    g_shop_npc_id = cw.INVALID_ENTITY
    if g_playing_state == .Shop {
        set_playing_state(.Hub if g_hub_active else .Gameplay)
    }
}

@(private = "file")
_clear_all_shop_stock :: proc(w: ^cw.World) {
    npc_ids := cw.world_query(w, cw.query_mask(.NPC))
    defer delete(npc_ids)
    for id in npc_ids {
        if cw.world_is_valid(w, id) {
            shop_clear_stock(w, id)
        }
    }
}

hub_apply :: proc(w: ^cw.World) {
    has_shopkeeper := false
    has_mutation_workbench := false
    for npc in g_level_data.npcs {
        switch npc.npc_type {
        case .Shopkeeper:
            has_shopkeeper = true
        case .MutationWorkbench:
            has_mutation_workbench = true
        }
    }

    if !has_shopkeeper {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_shopkeeper"))
        if npc_id != cw.INVALID_ENTITY {
            if cw.world_has_component(w, npc_id, .Transform) {
                cw.world_get_transform(w, npc_id).position = HUB_SHOPKEEPER_POS
            }
            cw.world_set_wallet(w, npc_id, cw.WalletComp{ gold = 200 })
            shop_roll_stock(w, npc_id, 0)
        }
    }

    if !has_mutation_workbench {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_mutation_workbench"))
        if npc_id != cw.INVALID_ENTITY && cw.world_has_component(w, npc_id, .Transform) {
            cw.world_get_transform(w, npc_id).position = HUB_MUTATION_WORKBENCH_POS
        }
    }
}

spawn_extraction_point :: proc(w: ^cw.World) {
    ext_id := cw.world_create_entity(w)
    cw.world_set_transform(w, ext_id, cw.TransformComp{
        position = { 12 * TILE_SIZE, 7 * TILE_SIZE, 0 },
    })
    cw.world_set_extraction(w, ext_id, cw.ExtractionComp{
        interact_radius = EXTRACT_RADIUS,
        activate_time   = EXTRACT_TIME,
    })
}

level_do_switch :: proc(w: ^cw.World, n: int) {
    level_clear(w)        // destroys everything including players; resets pending flag
    director_init()
    level_load(n)
    level_apply(w)
    spawn_extraction_point(w)
    spawn_players(w)
}


extraction_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update       { return }
    if g_playing_state != .Gameplay { return }

    if g_raid_timer > 0 {
        g_raid_timer -= dt
        if g_raid_timer <= 0 {
            g_raid_timer = 0
            if cw.world_is_valid(w, w.player_id) {
                on_player_death(w)
            }
            return
        }
    }

    pid := w.player_id
    if !cw.world_is_valid(w, pid)                    { return }
    if !cw.world_has_component(w, pid, .Transform)   { return }

    pt := cw.world_get_transform(w, pid).position

    ids := cw.world_query(w, cw.query_mask(.Extraction, .Transform))
    defer delete(ids)

    for eid in ids {
        ext := cw.world_get_extraction(w, eid)
        if ext.activated { continue }
        et  := cw.world_get_transform(w, eid).position
        dx  := pt[0] - et[0]
        dy  := pt[1] - et[1]
        dist := math.sqrt(dx*dx + dy*dy)

        if dist <= ext.interact_radius {
            ext.timer += dt
            if ext.timer >= ext.activate_time {
                ext.activated = true
                on_player_extract(w)
            }
        } else {
            ext.timer = 0
        }
    }
}

on_player_extract :: proc(w: ^cw.World) {
    extract_val := compute_extract_value(w, w.player_id)
    g_lifetime_stats.successful_raids += 1
    if extract_val > int(g_lifetime_stats.max_extract_gold) {
        g_lifetime_stats.max_extract_gold = i32(extract_val)
    }

    gold_earned := 0
    if cw.world_has_component(w, w.player_id, .Wallet) {
        wallet       := cw.world_get_wallet(w, w.player_id)
        gold_earned   = wallet.gold
        g_stash.gold += gold_earned
        wallet.gold   = 0
    }
    raid_result_gold = gold_earned

    serums_earned := 0
    if cw.world_has_component(w, w.player_id, .Inventory) {
        inv := cw.world_get_inventory(w, w.player_id)
        for cell_id in inv.backpack {
            if cell_id == cw.INVALID_ENTITY { continue }
            if !cw.world_is_valid(w, cell_id) { continue }
            if cw.world_has_component(w, cell_id, .Item) {
                item := cw.world_get_item(w, cell_id)
                if item.serum_value > 0 && item.pack_x >= 0 {
                    serums_earned += item.serum_value
                }
            }
        }
    }

    serums_earned = _count_serum_value(w)
    g_stash.serums   += serums_earned
    raid_result_serums = serums_earned

    set_playing_state(.ExtractScreen)
}

@(private = "file")
_count_serum_value :: proc(w: ^cw.World) -> int {
    if !cw.world_has_component(w, w.player_id, .Inventory) { return 0 }
    inv   := cw.world_get_inventory(w, w.player_id)
    total := 0
    for row in 0..<cw.BACKPACK_ROWS {
        for col in 0..<cw.BACKPACK_COLS {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id == cw.INVALID_ENTITY  { continue }
            if !cw.world_is_valid(w, cell_id) { continue }
            if !cw.world_has_component(w, cell_id, .Item) { continue }
            item := cw.world_get_item(w, cell_id)
            if item.serum_value > 0 && item.pack_x == col && item.pack_y == row {
                total += item.serum_value
            }
        }
    }
    return total
}

on_player_death :: proc(w: ^cw.World) {
    g_lifetime_stats.deaths += 1
    raid_result_gold   = 0
    raid_result_serums = 0
    strip_player_carried(w, w.player_id)
    if cw.world_is_valid(w, w.player_id) {
        save_player(w, w.player_id)
    }
    set_playing_state(.DeathScreen)
}

level_exit_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate        { return }
    if g_pending_level_switch != 0 { return }

    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid) { continue }
        if !cw.world_has_component(w, pid, .Transform) { continue }

        pos      := cw.world_get_transform(w, pid).position
        xPos, yPos := world_to_tile(pos[0], pos[1])

        for ex in g_level_data.exits {
            if int(ex.tx) == xPos && int(ex.ty) == yPos {
                on_player_extract(w)
                return
            }
        }
    }
}
