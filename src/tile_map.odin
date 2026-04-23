package main

import rl   "vendor:raylib"
import      "core:math"

TileType :: enum u8 {
    Floor = 1,
    Wall  = 2,
    Water = 3,
}

DEFAULT_LEVEL_COLS :: 32
DEFAULT_LEVEL_ROWS :: 20

tilemap_fill_default :: proc() {
    clear(&g_tilemap)
    half_c := DEFAULT_LEVEL_COLS / 2   // 16
    half_r := DEFAULT_LEVEL_ROWS / 2   // 10
    for y in -half_r..<half_r {
        for x in -half_c..<half_c {
            is_border := x == -half_c || y == -half_r ||
                         x == half_c-1 || y == half_r-1
            tt := TileType.Wall if is_border else TileType.Floor
            g_tilemap[[2]int{x, y}] = tt
        }
    }
}

g_tilemap: map[[2]int]TileType

TileSpriteEntry :: struct {
    tex:     rl.Texture2D,
    src:     rl.Rectangle,
    rt:      rl.RenderTexture2D,
    from_rt: bool,
}

g_tile_sprites: [4]TileSpriteEntry

@(private = "file")
build_tile_sprite :: proc(tt: TileType) -> TileSpriteEntry {
    size := i32(TILE_SIZE)
    rt := rl.LoadRenderTexture(size, size)
    rl.BeginTextureMode(rt)
    rl.ClearBackground(rl.BLANK)

    switch tt {
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
load_tile_sprite :: proc(stem: string, tt: TileType) -> TileSpriteEntry {
    path_buf: [256]u8
    n := copy(path_buf[:], "data/sprites/tiles/")
    n += copy(path_buf[n:], stem)
    n += copy(path_buf[n:], ".png")
    path_buf[n] = 0

    loaded := rl.LoadTexture(cstring(&path_buf[0]))
    if loaded.id != 0 {
        rl.SetTextureFilter(loaded, .POINT)
        return TileSpriteEntry{
            tex = loaded,
            src = { 0, 0, f32(loaded.width), f32(loaded.height) },
        }
    }
    return build_tile_sprite(tt)
}

tilemap_init :: proc() {
    g_tilemap = make(map[[2]int]TileType)
    g_tile_sprites[int(TileType.Floor)] = load_tile_sprite("floor", .Floor)
    g_tile_sprites[int(TileType.Wall)]  = load_tile_sprite("wall", .Wall)
    g_tile_sprites[int(TileType.Water)] = load_tile_sprite("water", .Water)
}

tilemap_destroy :: proc() {
    for i in 0..<len(g_tile_sprites) {
        entry := g_tile_sprites[i]
        if entry.from_rt {
            if entry.rt.id != 0 { rl.UnloadRenderTexture(entry.rt) }
        } else if entry.tex.id != 0 {
            rl.UnloadTexture(entry.tex)
        }
    }
    delete(g_tilemap)
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

tile_is_walkable :: proc(tx, ty: int) -> bool {
    return tile_at(tx, ty) == .Floor
}

tile_exists :: proc(tx, ty: int) -> bool {
    _, ok := g_tilemap[[2]int{tx, ty}]
    return ok
}

// wall_has_floor_neighbor returns true when at least one of the 8 neighbours
// is a Floor tile.  Used to distinguish visible interior walls (next to the
// playable area) from invisible border/void walls that should not be drawn.
wall_has_floor_neighbor :: proc(tx, ty: int) -> bool {
    for dy in -1..=1 {
        for dx in -1..=1 {
            if dx == 0 && dy == 0 { continue }
            if tile_at(tx + dx, ty + dy) == .Floor { return true }
        }
    }
    return false
}

draw_tilemap :: proc() {
    for k, v in g_tilemap {
        x := f32(k[0] * TILE_SIZE)
        y := f32(k[1] * TILE_SIZE)
        ts := f32(TILE_SIZE)
        entry := g_tile_sprites[int(v)]
        dst := rl.Rectangle{ x, y, ts, ts }
        switch v {
        case .Floor:
            rl.DrawTexturePro(entry.tex, entry.src, dst, {0, 0}, 0, rl.WHITE)
        case .Wall:
            rl.DrawTexturePro(entry.tex, entry.src, dst, {0, 0}, 0, rl.WHITE)
        case .Water:
            t_anim  := f32(rl.GetTime())
            wave    := math.sin(t_anim * 1.8 + (x + y) * 0.07) * 0.5 + 0.5
            tint := rl.Color{
                u8(42 + int(wave * 20)),
                u8(84 + int(wave * 24)),
                u8(140 + int(wave * 30)),
                255,
            }
            rl.DrawTexturePro(entry.tex, entry.src, dst, {0, 0}, 0, tint)
        }
    }
}
