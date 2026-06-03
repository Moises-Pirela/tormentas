package main

import rl    "vendor:raylib"
import       "core:math"
import slice "core:slice"

TileType :: enum u8 {


    Floor  = 1,
    Wall   = 2,
    Water  = 3,
    Pillar = 4,

    Floor1 = 5,
    Floor2 = 6,
    Floor3 = 7,
    Floor4 = 8,
    Wall1  = 9,
    Wall2  = 10,
    Wall3  = 11,
    Pillar1 = 12,
    Pillar2 = 13,
}


TileOverlay :: enum u8 {
    None  = 0,
    Oil   = 1,
    Fire  = 2,
}

DEFAULT_LEVEL_COLS :: 32
DEFAULT_LEVEL_ROWS :: 20

tilemap_fill_default :: proc() {
    clear(&g_tilemap)
    clear(&g_overlay_map)
    half_c := DEFAULT_LEVEL_COLS / 2
    half_r := DEFAULT_LEVEL_ROWS / 2
    for y in -half_r..<half_r {
        for x in -half_c..<half_c {
            is_border := x == -half_c || y == -half_r ||
                         x == half_c-1 || y == half_r-1
            tt := TileType.Wall if is_border else TileType.Floor
            g_tilemap[[2]int{x, y}] = tt
        }
    }
}

g_tilemap:     map[[2]int]TileType
g_overlay_map: map[[2]int]TileOverlay


g_door_blockers: map[[2]int]int

door_blockers_init    :: proc() { g_door_blockers = make(map[[2]int]int) }
door_blockers_destroy :: proc() { delete(g_door_blockers) }
door_blockers_clear   :: proc() { clear(&g_door_blockers) }

TileSpriteEntry :: struct {
    tex:     rl.Texture2D,
    src:     rl.Rectangle,
    rt:      rl.RenderTexture2D,
    from_rt: bool,
}

MAX_TILE_VARIANTS :: 4


g_tile_variants:       [5][MAX_TILE_VARIANTS]TileSpriteEntry
g_tile_variant_count:  [5]int

@(private = "file")
_build_tile_sprite :: proc(tt: TileType) -> TileSpriteEntry {
    size := i32(TILE_SIZE)
    rt := rl.LoadRenderTexture(size, size)
    rl.BeginTextureMode(rt)
    rl.ClearBackground(rl.BLANK)

    #partial switch tt {
    case .Floor:
        rl.ClearBackground(rl.Color{ 28, 26, 22, 255 })
        rl.DrawRectangle(0, 0, size, 6, rl.Color{ 34, 32, 27, 255 })
        rl.DrawRectangle(0, size - 8, size, 8, rl.Color{ 20, 18, 15, 255 })
        rl.DrawRectangle(4, 8, 14, 10, rl.Color{ 31, 29, 24, 255 })
        rl.DrawRectangle(22, 12, 12, 8, rl.Color{ 25, 23, 19, 255 })
        rl.DrawRectangle(10, 24, 18, 10, rl.Color{ 33, 31, 26, 255 })
        rl.DrawRectangle(2, 20, 6, 6, rl.Color{ 40, 36, 29, 120 })
        rl.DrawRectangle(30, 4, 6, 6, rl.Color{ 48, 42, 34, 90 })
    case .Wall:
        rl.ClearBackground(rl.Color{ 58, 50, 42, 255 })
        rl.DrawRectangle(0, 0, size, 7, rl.Color{ 102, 88, 68, 255 })
        rl.DrawRectangle(0, size - 6, size, 6, rl.Color{ 28, 24, 20, 255 })
        rl.DrawRectangle(3, 10, 14, 11, rl.Color{ 69, 60, 50, 255 })
        rl.DrawRectangle(19, 9, 18, 12, rl.Color{ 79, 68, 56, 255 })
        rl.DrawRectangle(6, 24, 12, 10, rl.Color{ 76, 64, 52, 255 })
        rl.DrawRectangle(20, 23, 15, 11, rl.Color{ 65, 56, 47, 255 })
        rl.DrawLine(18, 8, 18, 34, rl.Color{ 32, 26, 20, 120 })
    case .Water:
        rl.ClearBackground(rl.Color{ 24, 50, 82, 255 })
        rl.DrawRectangle(0, 0, size, 5, rl.Color{ 54, 92, 138, 200 })
        rl.DrawRectangle(4, 10, 14, 4, rl.Color{ 78, 126, 182, 110 })
        rl.DrawRectangle(18, 18, 16, 4, rl.Color{ 62, 116, 170, 110 })
        rl.DrawRectangle(8, 28, 20, 4, rl.Color{ 86, 144, 196, 110 })
        rl.DrawRectangle(0, size - 7, size, 7, rl.Color{ 12, 28, 50, 170 })
    case .Pillar:
        rl.ClearBackground(rl.Color{ 48, 42, 36, 255 })
        rl.DrawRectangle(8, 4, 20, 28, rl.Color{ 72, 62, 52, 255 })
        rl.DrawRectangle(10, 2, 16, 4, rl.Color{ 96, 82, 64, 255 })
        rl.DrawRectangle(10, 30, 16, 4, rl.Color{ 28, 22, 16, 255 })
        rl.DrawLine(8, 4, 8, 32, rl.Color{ 24, 18, 14, 160 })
        rl.DrawLine(28, 4, 28, 32, rl.Color{ 88, 74, 58, 140 })
    }

    rl.EndTextureMode()
    return TileSpriteEntry{
        tex     = rt.texture,
        src     = { 0, 0, f32(size), -f32(size) },
        rt      = rt,
        from_rt = true,
    }
}


@(private = "file")
_load_tile_variants :: proc(ti: int, stem: string, tt: TileType) {
    count := 0
    path_buf: [256]u8
    for v in 1..=MAX_TILE_VARIANTS {
        n := copy(path_buf[:], "data/sprites/tiles/")
        n += copy(path_buf[n:], stem)

        path_buf[n] = '_'; path_buf[n+1] = '0'; path_buf[n+2] = u8('0' + v)
        n += 3
        n += copy(path_buf[n:], ".png")
        path_buf[n] = 0

        loaded := rl.LoadTexture(cstring(&path_buf[0]))
        if loaded.id != 0 {
            rl.SetTextureFilter(loaded, .BILINEAR)
            g_tile_variants[ti][count] = TileSpriteEntry{
                tex = loaded,
                src = { 0, 0, f32(loaded.width), f32(loaded.height) },
            }
            count += 1
        } else {
            break
        }
    }
    if count == 0 {

        g_tile_variants[ti][0] = _build_tile_sprite(tt)
        count = 1
    }
    g_tile_variant_count[ti] = count
}

tilemap_init :: proc() {
    g_tilemap     = make(map[[2]int]TileType)
    g_overlay_map = make(map[[2]int]TileOverlay)
    _load_tile_variants(int(TileType.Floor),  "floor",  .Floor)
    _load_tile_variants(int(TileType.Wall),   "wall",   .Wall)
    _load_tile_variants(int(TileType.Water),  "water",  .Water)
    _load_tile_variants(int(TileType.Pillar), "pillar", .Pillar)
}

tilemap_destroy :: proc() {
    for ti in 0..<len(g_tile_variants) {
        n := g_tile_variant_count[ti]
        for i in 0..<n {
            entry := g_tile_variants[ti][i]
            if entry.from_rt {
                if entry.rt.id != 0 { rl.UnloadRenderTexture(entry.rt) }
            } else if entry.tex.id != 0 {
                rl.UnloadTexture(entry.tex)
            }
        }
    }
    delete(g_tilemap)
    delete(g_overlay_map)
}

world_to_tile :: proc(wx, wy: f32) -> (tx, ty: int) {
    tx = int(math.floor(wx / f32(TILE_SIZE)))
    ty = int(math.floor(wy / f32(TILE_SIZE)))
    return
}

tile_at :: proc(tx, ty: int) -> TileType {
    v, _ := g_tilemap[[2]int{tx, ty}]
    return v
}

overlay_at :: proc(tx, ty: int) -> TileOverlay {
    v, _ := g_overlay_map[[2]int{tx, ty}]
    return v
}

tile_is_walkable :: proc(tx, ty: int) -> bool {
    if tile_base(tile_at(tx, ty)) != .Floor { return false }
    _, blocked := g_door_blockers[[2]int{tx, ty}]
    return !blocked
}

tile_exists :: proc(tx, ty: int) -> bool {
    _, ok := g_tilemap[[2]int{tx, ty}]
    return ok
}


wall_has_floor_neighbor :: proc(tx, ty: int) -> bool {
    for dy in -1..=1 {
        for dx in -1..=1 {
            if dx == 0 && dy == 0 { continue }
            if tile_base(tile_at(tx + dx, ty + dy)) == .Floor { return true }
        }
    }
    return false
}


tile_base :: proc(tt: TileType) -> TileType {
    #partial switch tt {
    case .Floor1, .Floor2, .Floor3, .Floor4:  return .Floor
    case .Wall1,  .Wall2,  .Wall3:            return .Wall
    case .Pillar1, .Pillar2:                  return .Pillar
    }
    return tt
}


@(private = "file")
_tile_cat_vi :: proc(tt: TileType) -> (cat: int, vi: int) {
    #partial switch tt {
    case .Floor:   return int(TileType.Floor),   -1
    case .Floor1:  return int(TileType.Floor),    0
    case .Floor2:  return int(TileType.Floor),    1
    case .Floor3:  return int(TileType.Floor),    2
    case .Floor4:  return int(TileType.Floor),    3
    case .Wall:    return int(TileType.Wall),    -1
    case .Wall1:   return int(TileType.Wall),     0
    case .Wall2:   return int(TileType.Wall),     1
    case .Wall3:   return int(TileType.Wall),     2
    case .Water:   return int(TileType.Water),   -1
    case .Pillar:  return int(TileType.Pillar),  -1
    case .Pillar1: return int(TileType.Pillar),   0
    case .Pillar2: return int(TileType.Pillar),   1
    }
    return int(tt), -1
}


@(private = "file")
_tile_variant :: proc(tt: TileType, tx, ty: int) -> TileSpriteEntry {
    cat, vi := _tile_cat_vi(tt)
    count   := g_tile_variant_count[cat]
    if count == 0 { return {} }
    if vi >= 0 {

        return g_tile_variants[cat][min(vi, count - 1)]
    }
    if count == 1 { return g_tile_variants[cat][0] }

    h := u32(tx) * 2654435761 ~ u32(ty) * 2246822519
    h ~= h >> 16
    h *= 0x45d9f3b
    h ~= h >> 16
    return g_tile_variants[cat][int(h) % count]
}

TileSortEntry :: struct { tx, ty: int, v: TileType }

draw_tilemap :: proc() {
    t_anim := f32(rl.GetTime())


    min_x, min_y, max_x, max_y := cartesian_view_bounds(f32(TILE_SIZE))


    sorted := make([]TileSortEntry, len(g_tilemap), context.temp_allocator)
    n := 0
    for k, v in g_tilemap {
        wx := f32(k[0] * TILE_SIZE)
        wy := f32(k[1] * TILE_SIZE)
        if wx < min_x || wx > max_x || wy < min_y || wy > max_y { continue }
        sorted[n] = TileSortEntry{ k[0], k[1], v }
        n += 1
    }
    sorted = sorted[:n]
    slice.sort_by(sorted, proc(a, b: TileSortEntry) -> bool {
        return a.tx + a.ty < b.tx + b.ty
    })

    for tile in sorted {
        tx, ty := tile.tx, tile.ty
        v      := tile.v
        center, top, right, bottom, left := iso_tile_bounds(tx, ty)
        entry := _tile_variant(v, tx, ty)


        dst := rl.Rectangle{
            center.x - ISO_TILE_W,
            center.y - ISO_TILE_H,
            ISO_TILE_W * 2,
            ISO_TILE_H * 2,
        }
        #partial switch tile_base(v) {
        case .Floor:
            floor_src := rl.Rectangle{ 0, 0, entry.src.width, entry.src.width * 0.5 }
            rl.DrawTexturePro(entry.tex, floor_src, dst, {0, 0}, 0, rl.WHITE)


            switch overlay_at(tx, ty) {
            case .Oil:
                sheen := math.sin(t_anim * 1.4 + (center.x + center.y) * 0.018) * 0.5 + 0.5
                oil_tint := rl.Color{
                    u8(18 + int(sheen * 14)),
                    u8(14 + int(sheen * 10)),
                    u8(10 + int(sheen * 28)),
                    200,
                }
                rl.DrawRectangle(0, 0, 0, 0, rl.BLANK)
                rl.DrawTriangle(top, right, center, rl.Color{ 8,  10, 18, 210 })
                rl.DrawTriangle(top, left,  center, rl.Color{ 8,  10, 18, 210 })
                rl.DrawTriangle(bottom, right, center, rl.Color{ 4,  6, 12, 210 })
                rl.DrawTriangle(bottom, left,  center, rl.Color{ 4,  6, 12, 210 })
                rl.DrawTriangle(top, right, center, rl.Color{ 60, 90,  50, u8(sheen * 45) })
                rl.DrawTriangle(top, left,  center, rl.Color{ 50, 60,  90, u8(sheen * 35) })
                rl.DrawLineV(top,    right,  rl.Color{ 60, 80,  50, oil_tint.a })
                rl.DrawLineV(right,  bottom, rl.Color{ 30, 40,  70, oil_tint.a })
                rl.DrawLineV(bottom, left,   rl.Color{ 60, 40,  80, oil_tint.a })
                rl.DrawLineV(left,   top,    rl.Color{ 60, 80,  50, oil_tint.a })
            case .Fire:
                flicker := math.sin(t_anim * 4.5 + (center.x + center.y) * 0.016) * 0.5 + 0.5
                rl.DrawTriangle(top, right, center, rl.Color{ 70, 20, 5, 190 })
                rl.DrawTriangle(top, left,  center, rl.Color{ 55, 16, 4, 190 })
                rl.DrawTriangle(bottom, right, center, rl.Color{ 30, 10, 2, 200 })
                rl.DrawTriangle(bottom, left,  center, rl.Color{ 30, 10, 2, 200 })
                rl.DrawLineV(top,    right,  rl.Color{ 220, 100, 20, 140 })
                rl.DrawLineV(right,  bottom, rl.Color{  60,  18,  6,  90 })
                rl.DrawLineV(bottom, left,   rl.Color{  60,  18,  6,  90 })
                rl.DrawLineV(left,   top,    rl.Color{ 160,  60, 12, 120 })
                rl.DrawTriangle(top, right, center,
                    rl.Color{ 255, 120, 20, u8(flicker * 45) })
                rl.DrawTriangle(top, left, center,
                    rl.Color{ 200,  70,  8, u8(flicker * 32) })
            case .None:

            }

        case .Wall:


            wall_depth := ISO_TILE_W * 0.85


            floor_e   := _tile_variant(.Floor, tx, ty)
            floor_src := rl.Rectangle{ 0, 0, floor_e.src.width, floor_e.src.width * 0.5 }
            wall_top  := rl.Rectangle{
                center.x - ISO_TILE_W,
                center.y - ISO_TILE_H - wall_depth,
                ISO_TILE_W * 2,
                ISO_TILE_H * 2,
            }
            rl.DrawTexturePro(floor_e.tex, floor_src, wall_top, {0, 0}, 0, rl.Color{ 220, 210, 196, 255 })

            bottom_l := rl.Vector2{ left.x,   left.y   + wall_depth }
            bottom_r := rl.Vector2{ right.x,  right.y  + wall_depth }
            bottom_d := rl.Vector2{ bottom.x, bottom.y + wall_depth }


            face_r_rect := rl.Rectangle{
                center.x, right.y - wall_depth,
                ISO_TILE_W, wall_depth + ISO_TILE_H,
            }
            rl.DrawTexturePro(entry.tex, entry.src, face_r_rect, {0, 0}, 0, rl.Color{ 210, 195, 175, 255 })


            face_l_rect := rl.Rectangle{
                left.x, left.y - wall_depth,
                ISO_TILE_W, wall_depth + ISO_TILE_H,
            }
            rl.DrawTexturePro(entry.tex, entry.src, face_l_rect, {0, 0}, 0, rl.Color{ 130, 116, 98, 255 })


            face_col_l := rl.Color{ 0, 0, 0, 60 }
            face_col_r := rl.Color{ 255, 255, 255, 15 }
            rl.DrawTriangle(bottom, left, bottom_l, face_col_l)
            rl.DrawTriangle(bottom, bottom_l, bottom_d, face_col_l)
            rl.DrawTriangle(bottom, right, bottom_r, face_col_r)
            rl.DrawTriangle(bottom, bottom_r, bottom_d, face_col_r)


            rl.DrawLineV(top, right, rl.Color{ 180, 162, 132, 180 })
            rl.DrawLineV(right, bottom, rl.Color{ 18, 16, 12, 130 })
            rl.DrawLineV(bottom, left, rl.Color{ 26, 22, 18, 170 })
            rl.DrawLineV(left, top, rl.Color{ 110, 96, 74, 150 })
            rl.DrawLineV(left, bottom_l, rl.Color{ 18, 14, 12, 160 })
            rl.DrawLineV(bottom, bottom_d, rl.Color{ 18, 14, 12, 160 })
            rl.DrawLineV(right, bottom_r, rl.Color{ 30, 24, 18, 150 })

        case .Water:
            wave    := math.sin(t_anim * 1.8 + (center.x + center.y) * 0.02) * 0.5 + 0.5
            tint := rl.Color{
                u8(42 + int(wave * 20)),
                u8(84 + int(wave * 24)),
                u8(140 + int(wave * 30)),
                255,
            }
            water_src := rl.Rectangle{ 0, 0, entry.src.width, entry.src.width * 0.5 }
            rl.DrawTexturePro(entry.tex, water_src, dst, {0, 0}, 0, tint)
            rl.DrawTriangle(top, right, center, rl.Color{ 185, 225, 255, 22 })
            rl.DrawLineV(top, right, rl.Color{ 120, 180, 220, 120 })
            rl.DrawLineV(right, bottom, rl.Color{ 24, 40, 70, 140 })
            rl.DrawLineV(bottom, left, rl.Color{ 24, 40, 70, 140 })
            rl.DrawLineV(left, top, rl.Color{ 120, 180, 220, 120 })

        case .Pillar:

            floor_pe  := _tile_variant(.Floor, tx, ty)
            floor_src := rl.Rectangle{ 0, 0, floor_pe.src.width, floor_pe.src.width * 0.5 }
            rl.DrawTexturePro(floor_pe.tex, floor_src, dst, {0, 0}, 0,
                rl.Color{ 200, 196, 188, 255 })


            col_w     := ISO_TILE_W * 0.35
            col_depth := ISO_TILE_W * 1.8
            col_x     := center.x - col_w * 0.5
            col_top_y := center.y - col_depth


            cap_w   := col_w * 2.0
            cap_h   := col_w
            cap_r   := rl.Rectangle{ center.x - cap_w*0.5, col_top_y, cap_w, cap_h }
            rl.DrawTexturePro(floor_pe.tex, floor_src, cap_r, {0, 0}, 0,
                rl.Color{ 215, 208, 195, 255 })


            face_r := rl.Rectangle{ center.x, col_top_y + cap_h, col_w, col_depth - cap_h }
            rl.DrawTexturePro(entry.tex, entry.src, face_r, {0, 0}, 0,
                rl.Color{ 205, 192, 172, 255 })

            face_l := rl.Rectangle{ col_x, col_top_y + cap_h, col_w, col_depth - cap_h }
            rl.DrawTexturePro(entry.tex, entry.src, face_l, {0, 0}, 0,
                rl.Color{ 130, 118, 100, 255 })


            rl.DrawLineEx({col_x,          col_top_y + cap_h}, {col_x,          center.y}, 1, rl.Color{18,14,10,180})
            rl.DrawLineEx({col_x + col_w*2,col_top_y + cap_h}, {col_x + col_w*2, center.y}, 1, rl.Color{110,94,74,150})
        }
    }
}
