package main

import "core:os"
import "core:fmt"
import "core:math"
import p2p "p2p"

LEVEL_DIR :: "data/levels"

g_available_levels: int

level_scan_available :: proc() -> int {
    MAX_SCAN :: 64
    for n in 1 ..= MAX_SCAN {
        if !os.exists(level_path(n)) { return n - 1 }
    }
    return MAX_SCAN
}

@(private = "file")
_LegacySpawn :: struct {
    tx, ty: i16,
}

@(private = "file")
_LegacyExit :: struct {
    tx, ty:       i16,
    target_level: u16,
}

@(private = "file")
_LegacyLight :: struct {
    tx, ty:    i16,
    r, g, b:   u8,
    radius:    f32,
    intensity: f32,
}

@(private = "file")
_LegacyDoor :: struct {
    tx, ty:    i16,
    link_id:   u8,
    key_id:    u8,
    is_locked: bool,
}

LevelNPC :: struct {
    tx, ty:   i16,
    npc_type: NPCType,
}

LevelBarrel :: struct {
    tx, ty: i16,
    btype:  u8,
}

LevelSwitch :: struct {
    tx, ty:  i16,
    link_id: u8,
    flags:   u8,
}

LevelContainer :: struct {
    tx, ty:        i16,
    kind:          ContainerKind,
    loot_table_id: u8,
    gold_min:      u16,
    gold_max:      u16,
}

LevelLoreItem :: struct {
    tx, ty:  i16,
    lore_id: u8,
}

LevelPhonograph :: struct {
    tx, ty:       i16,
    recording_id: u8,
}

LevelKeyPickup :: struct {
    tx, ty: i16,
    key_id: u8,
}

LevelData :: struct {
    npcs:         [dynamic]LevelNPC,
    barrels:      [dynamic]LevelBarrel,

    switches:     [dynamic]LevelSwitch,
    containers:   [dynamic]LevelContainer,
    lore_items:   [dynamic]LevelLoreItem,
    phonographs:  [dynamic]LevelPhonograph,
    key_pickups:  [dynamic]LevelKeyPickup,
    modules:      [dynamic]LevelModule,
    entities:     [dynamic]LevelEntity,
    lighting:     LevelLightingConfig,

    cam_lims: [4]f32,
}

g_entity_defs: []EntityDef

g_level_data: LevelData

g_pending_level_switch: u16

RAID_TIME      :: f32(30 * 60)
EXTRACT_RADIUS :: f32(3 * TILE_SIZE)
EXTRACT_TIME   :: f32(30.0)

g_raid_timer: f32

level_data_init :: proc() {
    g_level_data.npcs         = make([dynamic]LevelNPC)
    g_level_data.barrels      = make([dynamic]LevelBarrel)
    g_level_data.switches     = make([dynamic]LevelSwitch)
    g_level_data.containers   = make([dynamic]LevelContainer)
    g_level_data.lore_items   = make([dynamic]LevelLoreItem)
    g_level_data.phonographs  = make([dynamic]LevelPhonograph)
    g_level_data.key_pickups  = make([dynamic]LevelKeyPickup)
    g_level_data.modules      = make([dynamic]LevelModule)
    g_level_data.entities     = make([dynamic]LevelEntity)
    g_level_data.lighting     = LIGHTING_CONFIG_DEFAULT
}

level_data_destroy :: proc() {
    delete(g_level_data.npcs)
    delete(g_level_data.barrels)
    delete(g_level_data.switches)
    delete(g_level_data.containers)
    delete(g_level_data.lore_items)
    delete(g_level_data.phonographs)
    delete(g_level_data.key_pickups)
    level_entities_clear()
    delete(g_level_data.entities)
}

@(private = "file")
level_path :: proc(n: int) -> string {
    return fmt.tprintf("%s/level%02d.bin", LEVEL_DIR, n)
}

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

lv_wstr :: proc(buf: ^[dynamic]u8, s: string) {
    n := min(len(s), 255)
    lv_wb1(buf, u8(n))
    for c in transmute([]u8)s[:n] { lv_wb1(buf, c) }
}

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

lv_rstr :: proc(raw: []u8, cur: int) -> (val: string, next: int, ok: bool) {
    n, c, o := lv_rb1(raw, cur)
    if !o { return "", cur, false }
    if c + int(n) > len(raw) { return "", cur, false }
    buf := make([]u8, int(n), context.temp_allocator)
    copy(buf, raw[c:c + int(n)])
    return string(buf), c + int(n), true
}

LEVEL_MAGIC   :: [4]u8{'T', 'R', 'M', 'T'}
LEVEL_VERSION :: u16(16)

level_save :: proc(n: int) {
    os.make_directory(LEVEL_DIR)

    buf := make([dynamic]u8, 0, 4096, context.temp_allocator)

    append(&buf, LEVEL_MAGIC[0], LEVEL_MAGIC[1], LEVEL_MAGIC[2], LEVEL_MAGIC[3])
    lv_wb2(&buf, LEVEL_VERSION)

    lv_wb4(&buf, u32(len(g_tilemap)))
    for k, v in g_tilemap {
        lv_wbi16(&buf, i16(k[0]))
        lv_wbi16(&buf, i16(k[1]))
        lv_wb1 (&buf, u8(v))
    }

    lv_wb4(&buf, u32(len(g_level_data.npcs)))
    for npc in g_level_data.npcs {
        lv_wbi16(&buf, npc.tx)
        lv_wbi16(&buf, npc.ty)
        lv_wb1 (&buf, u8(npc.npc_type))
    }

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

    lv_wbf32(&buf, cfg.sun_elevation)

    lv_wb4(&buf, u32(len(g_level_data.barrels)))
    for b in g_level_data.barrels {
        lv_wbi16(&buf, b.tx)
        lv_wbi16(&buf, b.ty)
        lv_wb1 (&buf, b.btype)
    }

    lv_wb4(&buf, u32(len(g_overlay_map)))
    for k, v in g_overlay_map {
        lv_wbi16(&buf, i16(k[0]))
        lv_wbi16(&buf, i16(k[1]))
        lv_wb1 (&buf, u8(v))
    }

    lv_wb4(&buf, u32(len(g_level_data.switches)))
    for s in g_level_data.switches {
        lv_wbi16(&buf, s.tx)
        lv_wbi16(&buf, s.ty)
        lv_wb1  (&buf, s.link_id)
        lv_wb1  (&buf, s.flags)
    }

    lv_wb4(&buf, u32(len(g_level_data.containers)))
    for c in g_level_data.containers {
        lv_wbi16(&buf, c.tx)
        lv_wbi16(&buf, c.ty)
        lv_wb1  (&buf, u8(c.kind))
        lv_wb1  (&buf, c.loot_table_id)
        lv_wb2  (&buf, c.gold_min)
        lv_wb2  (&buf, c.gold_max)
    }

    lv_wb4(&buf, u32(len(g_level_data.lore_items)))
    for li in g_level_data.lore_items {
        lv_wbi16(&buf, li.tx)
        lv_wbi16(&buf, li.ty)
        lv_wb1  (&buf, li.lore_id)
    }

    lv_wb4(&buf, u32(len(g_level_data.phonographs)))
    for ph in g_level_data.phonographs {
        lv_wbi16(&buf, ph.tx)
        lv_wbi16(&buf, ph.ty)
        lv_wb1  (&buf, ph.recording_id)
    }

    lv_wb4(&buf, u32(len(g_level_data.key_pickups)))
    for kp in g_level_data.key_pickups {
        lv_wbi16(&buf, kp.tx)
        lv_wbi16(&buf, kp.ty)
        lv_wb1  (&buf, kp.key_id)
    }

    lv_wb2(&buf, u16(g_ed_cell_size))
    lv_wb2(&buf, u16(g_ed_grid_cols))
    lv_wb2(&buf, u16(g_ed_grid_rows))

    for v in g_level_data.cam_lims { lv_wbf32(&buf, v) }

    lv_wb4(&buf, u32(len(g_hub_cell_map)))
    for k, v in g_hub_cell_map {
        lv_wbi16(&buf, i16(k[0]))
        lv_wbi16(&buf, i16(k[1]))
        lv_wb1  (&buf, u8(v))
    }

    lv_wb4(&buf, u32(len(g_level_data.modules)))
    for m in g_level_data.modules {
        name := ""
        if m.def_idx >= 0 && m.def_idx < len(g_modules) { name = g_modules[m.def_idx].id }
        lv_wb1(&buf, u8(min(len(name), 255)))
        for c in transmute([]u8)name { lv_wb1(&buf, c) }
        lv_wbi16(&buf, m.tx)
        lv_wbi16(&buf, m.ty)
    }

    lv_wb4(&buf, u32(len(g_level_data.entities)))
    for e in g_level_data.entities {
        lv_wstr(&buf, e.def)
        lv_wbf32(&buf, e.position[0])
        lv_wbf32(&buf, e.position[1])
        lv_wbf32(&buf, e.position[2])
        lv_wbf32(&buf, e.rotation)
        lv_wb4(&buf, u32(len(e.overrides)))
        for o in e.overrides {
            lv_wb1(&buf, u8(o.component))
            lv_wstr(&buf, o.path)
            lv_wstr(&buf, o.value)
        }
    }

    write_game_file(level_path(n), buf[:])
}

level_load :: proc(n: int) {
    g_level_data.lighting = LIGHTING_CONFIG_DEFAULT
    defer lighting_config_apply(g_level_data.lighting)

    raw, ok := read_game_file(level_path(n), context.temp_allocator)
    if !ok || len(raw) < 10 {
        tilemap_fill_default()
        clear(&g_level_data.npcs)
        clear(&g_level_data.barrels)
        clear(&g_level_data.switches)
        clear(&g_level_data.containers)
        clear(&g_level_data.lore_items)
        clear(&g_level_data.phonographs)
        clear(&g_level_data.key_pickups)
        clear(&g_level_data.modules)
        level_entities_clear()
        return
    }

    cur := 0

    if raw[0] != 'T' || raw[1] != 'R' || raw[2] != 'M' || raw[3] != 'T' {
        clear(&g_tilemap)
        clear(&g_overlay_map)
        clear(&g_level_data.npcs)
        clear(&g_level_data.barrels)
        clear(&g_level_data.switches)
        clear(&g_level_data.containers)
        clear(&g_level_data.lore_items)
        clear(&g_level_data.phonographs)
        clear(&g_level_data.key_pickups)
        return
    }
    cur = 4

    ver, ver_c, ver_ok := lv_rb2(raw, cur)

    if !ver_ok || ver < 1 || ver > LEVEL_VERSION {
        clear(&g_tilemap)
        clear(&g_overlay_map)
        clear(&g_level_data.npcs)
        clear(&g_level_data.barrels)
        clear(&g_level_data.switches)
        clear(&g_level_data.containers)
        clear(&g_level_data.lore_items)
        clear(&g_level_data.phonographs)
        clear(&g_level_data.key_pickups)
        return
    }
    cur = ver_c

    clear(&g_tilemap)
    clear(&g_overlay_map)
    tc, tc_c, tc_ok := lv_rb4(raw, cur)
    if !tc_ok { return }
    cur = tc_c
    for _ in 0..<tc {
        x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
        y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
        t,  tc2, tok  := lv_rb1  (raw, cur);  if !tok  { return };  cur = tc2
        key := [2]int{int(x), int(y)}
        if ver < 6 {
            switch t {
            case 4:
                g_tilemap[key]     = .Floor
                g_overlay_map[key] = .Oil
            case 5:
                g_tilemap[key]     = .Floor
                g_overlay_map[key] = .Fire
            case:
                tt := clamp(int(t), int(TileType.Floor), int(TileType.Pillar))
                g_tilemap[key] = TileType(tt)
            }
        } else {
            tt := clamp(int(t), int(TileType.Floor), int(TileType.Pillar2))
            g_tilemap[key] = TileType(tt)
        }
    }

    legacy_spawns: [dynamic]_LegacySpawn
    defer delete(legacy_spawns)
    legacy_exits: [dynamic]_LegacyExit
    defer delete(legacy_exits)
    legacy_player_start: [2]f32
    have_legacy_player_start := false
    if ver < 16 {
        sc, sc_c, sc_ok := lv_rb4(raw, cur)
        if !sc_ok { return }
        cur = sc_c
        for _ in 0..<sc {
            x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
            y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
            _,  ec,  eok  := lv_rb1  (raw, cur);  if !eok  { return };  cur = ec
            append(&legacy_spawns, _LegacySpawn{ tx = x, ty = y })
        }

        exc, exc_c, exc_ok := lv_rb4(raw, cur)
        if !exc_ok { return }
        cur = exc_c
        for _ in 0..<exc {
            x,  xc,  xok  := lv_rbi16(raw, cur);  if !xok  { return };  cur = xc
            y,  yc,  yok  := lv_rbi16(raw, cur);  if !yok  { return };  cur = yc
            tl, tlc, tlok := lv_rb2  (raw, cur);  if !tlok { return };  cur = tlc
            append(&legacy_exits, _LegacyExit{ tx = x, ty = y, target_level = tl })
        }

        px, pxc, pxok := lv_rbf32(raw, cur)
        if pxok {
            cur = pxc
            py, pyc, pyok := lv_rbf32(raw, cur)
            if pyok {
                legacy_player_start = {px, py}
                have_legacy_player_start = px != 0 || py != 0
                cur = pyc
            }
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
                npc_type := NPCType(clamp(int(nt), int(NPCType.Shopkeeper), int(NPCType.AbilityVendor)))
                append(&g_level_data.npcs, LevelNPC{
                    tx = nx,
                    ty = ny,
                    npc_type = npc_type,
                })
            }
        }
    }

    legacy_lights: [dynamic]_LegacyLight
    defer delete(legacy_lights)
    if ver >= 2 && ver < 16 {
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
                append(&legacy_lights, _LegacyLight{
                    tx = lx, ty = ly,
                    r = lr, g = lg, b = lb,
                    radius = rad, intensity = int_,
                })
            }
        }
    }

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

        if ver >= 14 {
            cur, ok1 = lf(raw, cur, &c.sun_elevation);      if !ok1 { return }
        }
    }

    clear(&g_level_data.barrels)
    if ver >= 5 {
        bc, bc_c, bc_ok := lv_rb4(raw, cur)
        if bc_ok {
            cur = bc_c
            for _ in 0..<bc {
                bx, bxc, bxok := lv_rbi16(raw, cur); if !bxok { break }; cur = bxc
                by, byc, byok := lv_rbi16(raw, cur); if !byok { break }; cur = byc
                bt, btc, btok := lv_rb1  (raw, cur); if !btok { break }; cur = btc
                append(&g_level_data.barrels, LevelBarrel{
                    tx = bx, ty = by, btype = bt,
                })
            }
        }
    }

    if ver >= 6 {
        oc, oc_c, oc_ok := lv_rb4(raw, cur)
        if oc_ok {
            cur = oc_c
            for _ in 0..<oc {
                ox, oxc, oxok := lv_rbi16(raw, cur); if !oxok { break }; cur = oxc
                oy, oyc, oyok := lv_rbi16(raw, cur); if !oyok { break }; cur = oyc
                ov, ovc, ovok := lv_rb1  (raw, cur); if !ovok { break }; cur = ovc
                ov_clamped := clamp(int(ov), int(TileOverlay.None), int(TileOverlay.Fire))
                if ov_clamped != 0 {
                    g_overlay_map[[2]int{int(ox), int(oy)}] = TileOverlay(ov_clamped)
                }
            }
        }
    }

    legacy_doors: [dynamic]_LegacyDoor
    defer delete(legacy_doors)
    if ver >= 7 && ver < 16 {
        dc, dcc, dcok := lv_rb4(raw, cur)
        if dcok {
            cur = dcc
            for _ in 0..<dc {
                dx,  dxc,  dxok  := lv_rbi16(raw, cur); if !dxok  { break }; cur = dxc
                dy,  dyc,  dyok  := lv_rbi16(raw, cur); if !dyok  { break }; cur = dyc
                dli, dlic, dliok := lv_rb1  (raw, cur); if !dliok { break }; cur = dlic
                dki, dkic, dkiok := lv_rb1  (raw, cur); if !dkiok { break }; cur = dkic
                _,   dotc, dotok := lv_rb1  (raw, cur); if !dotok { break }; cur = dotc
                dlk, dlkc, dlkok := lv_rb1  (raw, cur); if !dlkok { break }; cur = dlkc
                if cur + 24 > len(raw) { break }
                cur += 24
                append(&legacy_doors, _LegacyDoor{ tx = dx, ty = dy, link_id = dli, key_id = dki, is_locked = dlk != 0 })
            }
        }
    }

    clear(&g_level_data.switches)
    if ver >= 7 {
        swc, swcc, swcok := lv_rb4(raw, cur)
        if swcok {
            cur = swcc
            for _ in 0..<swc {
                sx,  sxc,  sxok  := lv_rbi16(raw, cur); if !sxok  { break }; cur = sxc
                sy,  syc,  syok  := lv_rbi16(raw, cur); if !syok  { break }; cur = syc
                sli, slic, sliok := lv_rb1  (raw, cur); if !sliok { break }; cur = slic
                sfl, sflc, sflok := lv_rb1  (raw, cur); if !sflok { break }; cur = sflc
                append(&g_level_data.switches, LevelSwitch{
                    tx = sx, ty = sy, link_id = sli, flags = sfl,
                })
            }
        }
    }

    clear(&g_level_data.containers)
    if ver >= 7 {
        cc, ccc, ccok := lv_rb4(raw, cur)
        if ccok {
            cur = ccc
            for _ in 0..<cc {
                ctx, ctxc, ctxok := lv_rbi16(raw, cur); if !ctxok { break }; cur = ctxc
                cty, ctyc, ctyok := lv_rbi16(raw, cur); if !ctyok { break }; cur = ctyc
                cki, ckic, ckiok := lv_rb1  (raw, cur); if !ckiok { break }; cur = ckic
                clt, cltc, cltok := lv_rb1  (raw, cur); if !cltok { break }; cur = cltc
                cgm, cgmc, cgmok := lv_rb2  (raw, cur); if !cgmok { break }; cur = cgmc
                cgx, cgxc, cgxok := lv_rb2  (raw, cur); if !cgxok { break }; cur = cgxc
                append(&g_level_data.containers, LevelContainer{
                    tx = ctx, ty = cty,
                    kind          = ContainerKind(clamp(int(cki), 0, 3)),
                    loot_table_id = clt,
                    gold_min      = cgm,
                    gold_max      = cgx,
                })
            }
        }
    }

    clear(&g_level_data.lore_items)
    if ver >= 7 {
        lic, licc, licok := lv_rb4(raw, cur)
        if licok {
            cur = licc
            for _ in 0..<lic {
                lx, lxc, lxok := lv_rbi16(raw, cur); if !lxok { break }; cur = lxc
                ly, lyc, lyok := lv_rbi16(raw, cur); if !lyok { break }; cur = lyc
                li, lic2, liok := lv_rb1 (raw, cur); if !liok { break }; cur = lic2
                append(&g_level_data.lore_items, LevelLoreItem{
                    tx = lx, ty = ly, lore_id = li,
                })
            }
        }
    }

    clear(&g_level_data.phonographs)
    if ver >= 7 {
        phc, phcc, phcok := lv_rb4(raw, cur)
        if phcok {
            cur = phcc
            for _ in 0..<phc {
                phx, phxc, phxok := lv_rbi16(raw, cur); if !phxok { break }; cur = phxc
                phy, phyc, phyok := lv_rbi16(raw, cur); if !phyok { break }; cur = phyc
                phi, phic, phiok := lv_rb1  (raw, cur); if !phiok { break }; cur = phic
                append(&g_level_data.phonographs, LevelPhonograph{
                    tx = phx, ty = phy, recording_id = phi,
                })
            }
        }
    }

    clear(&g_level_data.key_pickups)
    if ver >= 7 {
        kpc, kpcc, kpcok := lv_rb4(raw, cur)
        if kpcok {
            cur = kpcc
            for _ in 0..<kpc {
                kx, kxc, kxok := lv_rbi16(raw, cur); if !kxok { break }; cur = kxc
                ky, kyc, kyok := lv_rbi16(raw, cur); if !kyok { break }; cur = kyc
                ki, kic, kiok := lv_rb1  (raw, cur); if !kiok { break }; cur = kic
                append(&g_level_data.key_pickups, LevelKeyPickup{
                    tx = kx, ty = ky, key_id = ki,
                })
            }
        }
    }

    g_ed_cell_size = TILE_SIZE
    g_ed_grid_cols = DEFAULT_LEVEL_COLS
    g_ed_grid_rows = DEFAULT_LEVEL_ROWS
    if ver >= 10 {
        cs, csc, csok := lv_rb2(raw, cur); if csok { cur = csc; g_ed_cell_size = max(16, int(cs)) }
        gc, gcc, gcok := lv_rb2(raw, cur); if gcok { cur = gcc; g_ed_grid_cols = max(1,  int(gc)) }
        gr, grc, grok := lv_rb2(raw, cur); if grok { cur = grc; g_ed_grid_rows = max(1,  int(gr)) }
    }

    g_level_data.cam_lims = {}
    if ver >= 11 {
        for i in 0..<4 {
            v, vc, vok := lv_rbf32(raw, cur); if !vok { break }
            g_level_data.cam_lims[i] = v; cur = vc
        }
    }

    clear(&g_hub_cell_map)
    if ver >= 12 {
        hc, hcc, hcok := lv_rb4(raw, cur)
        if hcok {
            cur = hcc
            for _ in 0..<hc {
                hx, hxc, hxok := lv_rbi16(raw, cur); if !hxok { break }; cur = hxc
                hy, hyc, hyok := lv_rbi16(raw, cur); if !hyok { break }; cur = hyc
                hv, hvc, hvok := lv_rb1  (raw, cur); if !hvok { break }; cur = hvc
                g_hub_cell_map[[2]int{int(hx), int(hy)}] = TileType(hv)
            }
        }
    } else {
        scale := TILE_SIZE / HUB_CELL_RES
        for k, tt in g_tilemap {
            for sy in 0..<scale {
                for sx in 0..<scale {
                    g_hub_cell_map[[2]int{k[0]*scale+sx, k[1]*scale+sy}] = tt
                }
            }
        }
    }

    clear(&g_level_data.modules)
    level_entities_clear()
    for d in legacy_doors {
        wx := f32(int(d.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(d.ty) * TILE_SIZE + TILE_SIZE / 2)
        idx := level_entity_add("env_door", {wx, wy, 0})
        if d.link_id != 0  { level_entity_set_override(idx, .Openable, "link_id", fmt.tprintf("%d", d.link_id)) }
        if d.key_id != 0   { level_entity_set_override(idx, .Lockable, "key_id",  fmt.tprintf("%d", d.key_id)) }
        if d.is_locked     { level_entity_set_override(idx, .Lockable, "is_locked", "true") }
    }
    for sp in legacy_spawns {
        wx := f32(int(sp.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(sp.ty) * TILE_SIZE + TILE_SIZE / 2)
        level_entity_add("level_spawn_point", {wx, wy, 0})
    }
    for ex in legacy_exits {
        wx := f32(int(ex.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(ex.ty) * TILE_SIZE + TILE_SIZE / 2)
        idx := level_entity_add("level_exit", {wx, wy, 0})
        if ex.target_level != 0 {
            level_entity_set_override(idx, .LevelExit, "target_level", fmt.tprintf("%d", ex.target_level))
        }
    }
    for lt in legacy_lights {
        wx := f32(int(lt.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(lt.ty) * TILE_SIZE + TILE_SIZE / 2)
        idx := level_entity_add("level_light", {wx, wy, 0})
        level_entity_set_override(idx, .PointLight, "color[0]",  fmt.tprintf("%d", lt.r))
        level_entity_set_override(idx, .PointLight, "color[1]",  fmt.tprintf("%d", lt.g))
        level_entity_set_override(idx, .PointLight, "color[2]",  fmt.tprintf("%d", lt.b))
        level_entity_set_override(idx, .PointLight, "radius",    fmt.tprintf("%f", lt.radius))
        level_entity_set_override(idx, .PointLight, "intensity", fmt.tprintf("%f", lt.intensity))
    }
    if have_legacy_player_start {
        level_entity_add("level_player_start", {legacy_player_start[0], legacy_player_start[1], 0})
    }
    if ver >= 13 {
        mc, mcc, mcok := lv_rb4(raw, cur)
        if mcok {
            cur = mcc
            for _ in 0..<mc {
                nl, nlc, nlok := lv_rb1(raw, cur); if !nlok { break }; cur = nlc
                name_buf := make([]u8, int(nl), context.temp_allocator)
                bad := false
                for i in 0..<int(nl) {
                    b, bc, bok := lv_rb1(raw, cur); if !bok { bad = true; break }; cur = bc
                    name_buf[i] = b
                }
                if bad { break }
                mtx, mtxc, mtxok := lv_rbi16(raw, cur); if !mtxok { break }; cur = mtxc
                mty, mtyc, mtyok := lv_rbi16(raw, cur); if !mtyok { break }; cur = mtyc
                append(&g_level_data.modules, LevelModule{
                    def_idx = module_index_by_name(string(name_buf)),
                    tx = mtx, ty = mty,
                })
            }
        }
    }

    if ver >= 15 {
        ec, ecc, ecok := lv_rb4(raw, cur)
        if ecok {
            cur = ecc
            for _ in 0..<ec {
                edef, edc, edok := lv_rstr(raw, cur);  if !edok  { break }; cur = edc
                epx,  epxc, epxok := lv_rbf32(raw, cur); if !epxok { break }; cur = epxc
                epy,  epyc, epyok := lv_rbf32(raw, cur); if !epyok { break }; cur = epyc
                epz,  epzc, epzok := lv_rbf32(raw, cur); if !epzok { break }; cur = epzc
                erot, erc,  erok  := lv_rbf32(raw, cur); if !erok  { break }; cur = erc

                eidx := level_entity_add(edef, {epx, epy, epz}, erot)

                eoc, eocc, eocok := lv_rb4(raw, cur); if !eocok { break }; cur = eocc
                for _ in 0..<eoc {
                    ecmp, ecc2, ecok2 := lv_rb1(raw, cur);  if !ecok2 { break }; cur = ecc2
                    epath, epc, epok  := lv_rstr(raw, cur); if !epok  { break }; cur = epc
                    eval, evc, evok   := lv_rstr(raw, cur); if !evok  { break }; cur = evc
                    level_entity_set_override(eidx, ComponentType(ecmp), epath, eval)
                }
            }
        }
    }

    _ = cur

    g_wall_mask_dirty = true
}

level_apply :: proc(w: ^World) {
    spawn_level_npc :: proc(w: ^World, npc_type: NPCType, wx, wy: f32) -> int {
        def_name := ""
        switch npc_type {
        case .Shopkeeper:
            def_name = "npc_shopkeeper"
        case .MutationWorkbench:
            def_name = "npc_mutation_workbench"
        case .Stash:
            def_name = "npc_stash"
        case .AbilityVendor:
            def_name = "npc_ability_vendor"
        case .QuestBoard:
            def_name = "npc_quest_board"
        case .Quartermaster:
            def_name = "npc_quartermaster"
        case .Surgeon:
            def_name = "npc_surgeon"
        }
        if def_name == "" { return INVALID_ENTITY }

        id := spawn_from_def(w, find_entity_def(g_entity_defs, def_name))
        if id == INVALID_ENTITY { return id }
        if world_has_component(w, id, .Transform) {
            comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        }
        switch npc_type {
        case .Shopkeeper:
            comp_set(w, id, .Wallet, WalletComp{ gold = 200 })
            shop_roll_stock(w, id, 0)
        case .MutationWorkbench:
        case .Stash:
        case .AbilityVendor:
            ability_vendor_roll_stock(w, id, 0)
        case .QuestBoard, .Quartermaster, .Surgeon:
        }
        return id
    }

    for npc in g_level_data.npcs {
        wx := f32(int(npc.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(npc.ty) * TILE_SIZE + TILE_SIZE / 2)
        spawn_level_npc(w, npc.npc_type, wx, wy)
    }

    for b in g_level_data.barrels {
        wx := f32(int(b.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(b.ty) * TILE_SIZE + TILE_SIZE / 2)
        spawn_barrel(w, wx, wy, BarrelType(b.btype))
    }

    for s in g_level_data.switches {
        wx := f32(int(s.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(s.ty) * TILE_SIZE + TILE_SIZE / 2)
        id := spawn_from_def(w, find_entity_def(g_entity_defs, "env_switch"))
        if id == INVALID_ENTITY { continue }
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        is_toggle    := (s.flags & 0x01) != 0
        needs_weight := (s.flags & 0x02) != 0
        prompt: [48]u8
        if needs_weight {
            copy(prompt[:], "")
        } else {
            copy(prompt[:], string(t(.INTERACT_PULL_LEVER)))
        }
        comp_set(w, id, .Interactable, InteractableComp{
            radius = f32(TILE_SIZE) * 1.2,
            prompt = prompt,
            active = !needs_weight,
        })
        comp_set(w, id, .SignalEmitter, SignalEmitterComp{
            link_id      = s.link_id,
            is_on        = false,
            is_toggle    = is_toggle,
            needs_weight = needs_weight,
            weight_radius = f32(TILE_SIZE) * 0.6,
        })
    }

    for c in g_level_data.containers {
        wx := f32(int(c.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(c.ty) * TILE_SIZE + TILE_SIZE / 2)
        def_name := "env_chest" if c.kind == .Chest else "env_crate"
        id := spawn_from_def(w, find_entity_def(g_entity_defs, def_name))
        if id == INVALID_ENTITY { continue }
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        prompt: [48]u8
        switch c.kind {
        case .Chest:   copy(prompt[:], string(t(.INTERACT_OPEN_CHEST)))
        case .Crate:   copy(prompt[:], string(t(.INTERACT_BREAK_CRATE)))
        case .Locker:  copy(prompt[:], string(t(.INTERACT_OPEN_LOCKER)))
        case .Cabinet: copy(prompt[:], string(t(.INTERACT_SEARCH_CABINET)))
        }
        comp_set(w, id, .Interactable, InteractableComp{
            radius = f32(TILE_SIZE) * 1.2,
            prompt = prompt,
            active = true,
        })
        comp_set(w, id, .Container, ContainerComp{
            kind          = c.kind,
            is_open       = false,
            loot_table_id = c.loot_table_id,
            gold_min      = c.gold_min,
            gold_max      = c.gold_max,
        })
    }

    for li in g_level_data.lore_items {
        wx := f32(int(li.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(li.ty) * TILE_SIZE + TILE_SIZE / 2)
        id := spawn_from_def(w, find_entity_def(g_entity_defs, "env_lore_item"))
        if id == INVALID_ENTITY { continue }
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        prompt: [48]u8
        copy(prompt[:], string(t(.INTERACT_READ_DOCUMENT)))
        comp_set(w, id, .Interactable, InteractableComp{
            radius = f32(TILE_SIZE) * 1.2,
            prompt = prompt,
            active = true,
        })
        comp_set(w, id, .LoreItem, LoreItemComp{
            lore_id = li.lore_id,
            is_read = false,
        })
    }

    for ph in g_level_data.phonographs {
        wx := f32(int(ph.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(ph.ty) * TILE_SIZE + TILE_SIZE / 2)
        id := spawn_from_def(w, find_entity_def(g_entity_defs, "env_phonograph"))
        if id == INVALID_ENTITY { continue }
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        prompt: [48]u8
        copy(prompt[:], string(t(.INTERACT_WIND_PHONOGRAPH)))
        comp_set(w, id, .Interactable, InteractableComp{
            radius = f32(TILE_SIZE) * 1.5,
            prompt = prompt,
            active = true,
        })
        comp_set(w, id, .Phonograph, PhonographComp{
            recording_id = ph.recording_id,
            is_playing   = false,
        })
    }

    for kp in g_level_data.key_pickups {
        wx := f32(int(kp.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(kp.ty) * TILE_SIZE + TILE_SIZE / 2)
        id := spawn_from_def(w, find_entity_def(g_entity_defs, "env_key"))
        if id == INVALID_ENTITY { continue }
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
        prompt: [48]u8
        copy(prompt[:], string(t(.INTERACT_TAKE_KEY)))
        comp_set(w, id, .Interactable, InteractableComp{
            radius = f32(TILE_SIZE) * 1.0,
            prompt = prompt,
            active = true,
        })
        label: [40]u8
        comp_set(w, id, .KeyPickup, KeyPickupComp{
            key_id = kp.key_id,
            label  = label,
        })
    }

    level_entities_apply(w)
}

@(private = "file")
_slot_is_present :: proc(slot: int) -> bool {
    if slot == g_session.local_slot { return true }
    if !p2p.session_is_online(&g_session) { return false }
    if p2p.is_host(&g_session) {
        return p2p.session_peer_for_slot(&g_session, slot) != nil
    }
    return g_session.roster[slot].known
}

spawn_players :: proc(w: ^World) {
    ps: [2]f32
    start_ids := world_query(w, query_mask(.PlayerStart, .Transform))
    if len(start_ids) > 0 {
        p := comp_get(w, start_ids[0], .Transform, TransformComp).position
        ps = { p[0], p[1] }
    }
    delete(start_ids)
    SLOT_OFFSET    :: f32(60)

    for slot in 0..<MAX_PLAYERS {
        if !_slot_is_present(slot) { continue }
        sp: [3]f32
        if ps[0] != 0 || ps[1] != 0 {
            sp = { ps[0] + f32(slot) * SLOT_OFFSET, ps[1], 0 }
        } else {
            sp = { f32(slot) * SLOT_OFFSET, 0, 0 }
        }

        wep := spawn_from_def(w, find_entity_def(g_entity_defs, "weapon_pistol"))
        pid := spawn_from_def(w, find_entity_def(g_entity_defs, "player"))

        if world_has_component(w, pid, .Transform) {
            comp_get(w, pid, .Transform, TransformComp).position = sp
        }
        comp_set(w, pid, .Equipment, EquipmentComp{ weapon_entity_id = wep })
        comp_set(w, pid, .Inventory, inventory_make_empty())
        ensure_base_flasks(w, pid)
        comp_set(w, pid, .Respawn, RespawnComp{ spawn_pos = sp, delay = RESPAWN_DELAY })
        comp_set(w, pid, .Ability, AbilityComp{})
        comp_set(w, pid, .MutationContainer, mutation_container_empty())
        comp_set(w, pid, .Stats, StatsComp{
            strength    = 1,  dexterity  = 1, science    = 1,
            level       = 1,  xp         = 0, xp_next    = 100.0,
            stat_points = 0,  base_hp    = 100.0,
            base_energy = 100.0, base_speed = 240.0,
        })
        comp_set(w, pid, .Player, PlayerComp{ slot = slot })
        comp_set(w, pid, .Wallet, WalletComp{ gold = 0 })
        comp_set(w, pid, .StatusEffect, StatusEffectComp{})
        comp_set(w, pid, .KeyRing, KeyRingComp{})
        w.player_ids[slot] = pid
    }

    w.player_id = w.player_ids[w.local_player_slot]
    netcode_predictor_init()

    if ps[0] != 0 || ps[1] != 0 {
        g_camera.target = { ps[0], ps[1] }
    }
}

level_clear :: proc(w: ^World) {
    g_pending_level_switch = 0

    _clear_all_shop_stock(w)

    ai_paths_clear()
    door_blockers_clear()

    world_reset(w)

    if ui_has(.Shop) {
        ui_close(.Shop)
    } else {
        g_shop_npc_id = INVALID_ENTITY
    }
    if ui_has(.Stash) {
        ui_close(.Stash)
    } else {
        g_stash_npc_id = INVALID_ENTITY
    }
    if ui_has(.AbilityVendor) {
        ui_close(.AbilityVendor)
    } else {
        g_ability_vendor_npc_id = INVALID_ENTITY
    }
}

@(private = "file")
_clear_all_shop_stock :: proc(w: ^World) {
    npc_ids := world_query(w, query_mask(.NPC))
    defer delete(npc_ids)
    for id in npc_ids {
        if !world_is_valid(w, id) { continue }
        npc := comp_get(w, id, .NPC, NPCComp)
        switch npc.npc_type {
        case .Shopkeeper:
            shop_clear_stock(w, id)
        case .AbilityVendor:
            ability_vendor_clear_stock(w, id)
        case .MutationWorkbench, .Stash, .QuestBoard, .Quartermaster, .Surgeon:
        }
    }
}

hub_apply :: proc(w: ^World) {
    has_shopkeeper         := false
    has_mutation_workbench := false
    has_stash              := false
    has_ability_vendor     := false
    has_quest_board        := false
    for npc in g_level_data.npcs {
        switch npc.npc_type {
        case .Shopkeeper:
            has_shopkeeper = true
        case .MutationWorkbench:
            has_mutation_workbench = true
        case .Stash:
            has_stash = true
        case .AbilityVendor:
            has_ability_vendor = true
        case .QuestBoard:
            has_quest_board = true
        case .Quartermaster, .Surgeon:
        }
    }

    if !has_shopkeeper {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_shopkeeper"))
        if npc_id != INVALID_ENTITY {
            if world_has_component(w, npc_id, .Transform) {
                comp_get(w, npc_id, .Transform, TransformComp).position = HUB_SHOPKEEPER_POS
            }
            comp_set(w, npc_id, .Wallet, WalletComp{ gold = 200 })
            shop_roll_stock(w, npc_id, 0)
        }
    }

    if !has_mutation_workbench {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_mutation_workbench"))
        if npc_id != INVALID_ENTITY && world_has_component(w, npc_id, .Transform) {
            comp_get(w, npc_id, .Transform, TransformComp).position = HUB_MUTATION_WORKBENCH_POS
        }
    }

    if !has_stash {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_stash"))
        if npc_id != INVALID_ENTITY && world_has_component(w, npc_id, .Transform) {
            comp_get(w, npc_id, .Transform, TransformComp).position = HUB_STASH_POS
        }
    }

    if !has_ability_vendor {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_ability_vendor"))
        if npc_id != INVALID_ENTITY {
            if world_has_component(w, npc_id, .Transform) {
                comp_get(w, npc_id, .Transform, TransformComp).position = HUB_ABILITY_VENDOR_POS
            }
            ability_vendor_roll_stock(w, npc_id, 0)
        }
    }

    if !has_quest_board {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_quest_board"))
        if npc_id != INVALID_ENTITY && world_has_component(w, npc_id, .Transform) {
            comp_get(w, npc_id, .Transform, TransformComp).position = HUB_QUEST_BOARD_POS
        }
    }
}

hub_apply_quest_npcs :: proc(w: ^World) {
    has_quartermaster := false
    has_surgeon       := false
    npc_ids := world_query(w, query_mask(.NPC))
    defer delete(npc_ids)
    for nid in npc_ids {
        switch comp_get(w, nid, .NPC, NPCComp).npc_type {
        case .Quartermaster: has_quartermaster = true
        case .Surgeon:       has_surgeon       = true
        case .Shopkeeper, .MutationWorkbench, .Stash, .AbilityVendor, .QuestBoard:
        }
    }

    if quest_is_done(.Aberration) && !has_quartermaster {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_quartermaster"))
        if npc_id != INVALID_ENTITY && world_has_component(w, npc_id, .Transform) {
            comp_get(w, npc_id, .Transform, TransformComp).position = HUB_QUARTERMASTER_POS
        }
    }

    if quest_is_done(.PerfectRun) && !has_surgeon {
        npc_id := spawn_from_def(w, find_entity_def(g_entity_defs, "npc_surgeon"))
        if npc_id != INVALID_ENTITY && world_has_component(w, npc_id, .Transform) {
            comp_get(w, npc_id, .Transform, TransformComp).position = HUB_SURGEON_POS
        }
    }
}

spawn_extraction_at_tile :: proc(w: ^World, tx, ty: int) {
    ext_id := world_create_entity(w)
    comp_set(w, ext_id, .Transform, TransformComp{
        position = { f32(tx * TILE_SIZE + TILE_SIZE/2), f32(ty * TILE_SIZE + TILE_SIZE/2), 0 },
    })
    comp_set(w, ext_id, .Extraction, ExtractionComp{
        interact_radius = EXTRACT_RADIUS,
        activate_time   = EXTRACT_TIME,
    })
}

spawn_extraction_point :: proc(w: ^World) {
    spawn_extraction_at_tile(w, 12, 7)
}

level_spawn_extraction_zones :: proc(w: ^World) -> (found_zone: bool) {
    exit_ids := world_query(w, query_mask(.LevelExit, .Transform))
    defer delete(exit_ids)
    for id in exit_ids {
        le := comp_get(w, id, .LevelExit, LevelExitComp)
        if le.target_level != 0 { continue }
        p := comp_get(w, id, .Transform, TransformComp).position
        tx, ty := world_to_tile(p[0], p[1])
        spawn_extraction_at_tile(w, tx, ty)
        found_zone = true
    }
    if !found_zone {
        spawn_extraction_point(w)
    }
    return
}

level_do_switch :: proc(w: ^World, n: int) {
    fire_system_reset()
    level_clear(w)
    director_init()
    level_load(n)
    level_apply(w)
    door_init_blockers(w)

    level_spawn_extraction_zones(w)

    spawn_players(w)
}

extraction_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update       { return }
    if g_playing_state != .Gameplay { return }

    if g_raid_timer > 0 {
        g_raid_timer -= dt
        if g_raid_timer <= 0 {
            g_raid_timer = 0
            if world_is_valid(w, w.player_id) {
                on_player_death(w)
            }
            return
        }
    }

    ids := world_query(w, query_mask(.Extraction, .Transform))
    defer delete(ids)

    for eid in ids {
        ext := comp_get(w, eid, .Extraction, ExtractionComp)
        if ext.activated { continue }
        et := comp_get(w, eid, .Transform, TransformComp).position

        in_zone := false
        for slot in 0..<MAX_PLAYERS {
            pid := w.player_ids[slot]
            if !world_is_valid(w, pid)                  { continue }
            if !world_has_component(w, pid, .Transform) { continue }
            pt := comp_get(w, pid, .Transform, TransformComp).position
            dx := pt[0] - et[0]
            dy := pt[1] - et[1]
            if math.sqrt(dx*dx + dy*dy) <= ext.interact_radius { in_zone = true; break }
        }

        if in_zone {
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

on_player_extract :: proc(w: ^World) {
    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) { continue }

        extract_val := compute_extract_value(w, pid)

        gold := 0
        if world_has_component(w, pid, .Wallet) {
            wallet := comp_get(w, pid, .Wallet, WalletComp)
            gold    = wallet.gold
            wallet.gold = 0
        }
        serums := 0
        if world_has_component(w, pid, .MutationContainer) {
            serums = comp_get(w, pid, .MutationContainer, MutationContainerComp).serums
        }

        if slot == w.local_player_slot {
            _apply_raid_extract_local(w, pid, gold, serums, extract_val)
        } else if peer := p2p.session_peer_for_slot(&g_session, slot); peer != nil {
            p2p.session_send_raid_result_to_peer(peer, .Extracted, i32(gold), i32(serums), i32(extract_val),
                g_raid_enemies_killed, g_raid_elites_killed, g_raid_bosses_killed)
        }
    }

    quest_check_all(w)
    set_playing_state(.ExtractScreen)
}

@(private = "file")
_apply_raid_extract_local :: proc(w: ^World, pid: int, gold, serums, extract_val: int) {
    raid_result_gold = gold
    local_stash().gold += gold

    serums_earned := serums - g_raid_serums_start
    if serums_earned < 0 { serums_earned = 0 }
    raid_result_serums   = serums_earned
    local_stash().serums = serums

    g_lifetime_stats.successful_raids += 1
    if extract_val > int(g_lifetime_stats.max_extract_gold) {
        g_lifetime_stats.max_extract_gold = i32(extract_val)
    }
    if g_current_raid_level >= 2 {
        g_lifetime_stats.deep_extracts += 1
    }

    if world_is_valid(w, pid) { save_player(w, pid) }
}

on_player_death :: proc(w: ^World) {
    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) { continue }

        strip_player_carried(w, pid)
        ensure_base_flasks(w, pid)

        if slot == w.local_player_slot {
            _apply_raid_death_local(w, pid)
        } else if peer := p2p.session_peer_for_slot(&g_session, slot); peer != nil {
            p2p.session_send_raid_result_to_peer(peer, .Died, 0, 0, 0,
                g_raid_enemies_killed, g_raid_elites_killed, g_raid_bosses_killed)
        }

        if world_has_component(w, pid, .AnimState) {
            anim := comp_get(w, pid, .AnimState, AnimStateComp)
            anim.current_state = .Death
        }
    }

    set_playing_state(.DeathScreen)
}

@(private = "file")
_apply_raid_death_local :: proc(w: ^World, pid: int) {
    g_lifetime_stats.deaths += 1
    raid_result_gold   = 0
    raid_result_serums = 0
    if world_is_valid(w, pid) { save_player(w, pid) }
}

netcode_apply_raid_result :: proc(w: ^World) {
    if !g_session.has_raid_result { return }
    g_session.has_raid_result = false

    pid := w.player_id
    if !world_is_valid(w, pid) { return }

    g_lifetime_stats.enemies_killed += i32(g_session.raid_result_enemies_killed)
    g_lifetime_stats.elites_killed  += i32(g_session.raid_result_elites_killed)
    g_lifetime_stats.bosses_killed  += i32(g_session.raid_result_bosses_killed)

    switch g_session.raid_result_outcome {
    case .Extracted:
        if world_has_component(w, pid, .Wallet) {
            comp_get(w, pid, .Wallet, WalletComp).gold = 0
        }
        _apply_raid_extract_local(w, pid,
            int(g_session.raid_result_gold), int(g_session.raid_result_serums),
            int(g_session.raid_result_extract_value))
        set_playing_state(.ExtractScreen)

    case .Died:
        strip_player_carried(w, pid)
        _apply_raid_death_local(w, pid)
        set_playing_state(.DeathScreen)
    }

    quest_check_all(w)
}

level_exit_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .LateUpdate        { return }
    if g_pending_level_switch != 0 { return }

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) { continue }
        if !world_has_component(w, pid, .Transform) { continue }

        pos      := comp_get(w, pid, .Transform, TransformComp).position
        xPos, yPos := world_to_tile(pos[0], pos[1])

        exit_ids := world_query(w, query_mask(.LevelExit, .Transform))
        defer delete(exit_ids)
        for id in exit_ids {
            le := comp_get(w, id, .LevelExit, LevelExitComp)
            if le.target_level == 0 { continue }
            ep := comp_get(w, id, .Transform, TransformComp).position
            etx, ety := world_to_tile(ep[0], ep[1])
            if etx == xPos && ety == yPos {
                on_player_extract(w)
                return
            }
        }
    }
}
