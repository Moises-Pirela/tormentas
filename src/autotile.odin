package main

import rl  "vendor:raylib"
import     "core:fmt"

// ---------------------------------------------------------------------------
// 8-bit "blob" autotiling
//
// Paint a base tile type (Floor/Wall/…) and the correct edge/corner sprite is chosen
// at render time from a 47-tile set, based on which same-type neighbours connect. A
// corner only counts when both its adjacent edges also connect, which collapses the 256
// raw neighbour combinations down to exactly 47 meaningful ones.
//
// Neighbour bits (tile-grid space):
//     N = 1   E = 2   S = 4   W = 8
//     NE = 16 SE = 32 SW = 64 NW = 128
//
// Art delivery: data/sprites/tiles/<stem>_auto_NN.png for NN = 00..46, where NN is this
// system's blob index. Run the console command `autotile template` to export a reference
// image showing exactly which neighbours each index connects. The full 47-tile set must
// be present for a type to autotile; otherwise it falls back to the random variants.
// ---------------------------------------------------------------------------

AUTOTILE_COUNT :: 47

g_autotile:         [5][AUTOTILE_COUNT]TileSpriteEntry
g_autotile_present: [5]bool
g_blob47_index:     [256]int              // gated mask -> 0..46, or -1 if not a blob mask
g_blob47_mask:      [AUTOTILE_COUNT]int   // index -> the mask it represents (for the template)

@(private = "file")
_blob_valid :: proc(m: int) -> bool {
    n := m & 1 != 0; e := m & 2 != 0; s := m & 4 != 0; w := m & 8 != 0
    if (m & 16  != 0) && !(n && e) { return false }   // NE needs N and E
    if (m & 32  != 0) && !(s && e) { return false }   // SE needs S and E
    if (m & 64  != 0) && !(s && w) { return false }   // SW needs S and W
    if (m & 128 != 0) && !(n && w) { return false }   // NW needs N and W
    return true
}

autotile_build_table :: proc() {
    idx := 0
    for m in 0..<256 {
        if _blob_valid(m) {
            g_blob47_index[m] = idx
            g_blob47_mask[idx] = m
            idx += 1
        } else {
            g_blob47_index[m] = -1
        }
    }
    // idx is exactly AUTOTILE_COUNT (47) here.
}

@(private = "file")
_conn :: proc(base: TileType, x, y: int) -> bool {
    return tile_base(tile_at(x, y)) == base
}

autotile_mask :: proc(base: TileType, tx, ty: int) -> int {
    n := _conn(base, tx,   ty-1)
    e := _conn(base, tx+1, ty)
    s := _conn(base, tx,   ty+1)
    w := _conn(base, tx-1, ty)
    m := 0
    if n { m |= 1 }
    if e { m |= 2 }
    if s { m |= 4 }
    if w { m |= 8 }
    if n && e && _conn(base, tx+1, ty-1) { m |= 16 }
    if s && e && _conn(base, tx+1, ty+1) { m |= 32 }
    if s && w && _conn(base, tx-1, ty+1) { m |= 64 }
    if n && w && _conn(base, tx-1, ty-1) { m |= 128 }
    return m
}

autotile_load :: proc(cat: int, stem: string) {
    got := 0
    for i in 0..<AUTOTILE_COUNT {
        path_buf: [256]u8
        n := copy(path_buf[:], "data/sprites/tiles/")
        n += copy(path_buf[n:], stem)
        n += copy(path_buf[n:], "_auto_")
        path_buf[n]   = u8('0' + i / 10)
        path_buf[n+1] = u8('0' + i % 10)
        n += 2
        n += copy(path_buf[n:], ".png")
        path_buf[n] = 0

        loaded := rl.LoadTexture(cstring(&path_buf[0]))
        if loaded.id != 0 {
            rl.SetTextureFilter(loaded, .BILINEAR)
            g_autotile[cat][i] = TileSpriteEntry{
                tex = loaded,
                src = { 0, 0, f32(loaded.width), f32(loaded.height) },
            }
            got += 1
        }
    }
    g_autotile_present[cat] = got == AUTOTILE_COUNT
    if got > 0 && got < AUTOTILE_COUNT {
        fmt.eprintfln("[autotile] %s: %d/%d tiles found — need the full set; falling back to variants",
            stem, got, AUTOTILE_COUNT)
    }
}

autotile_destroy :: proc() {
    for c in 0..<5 {
        for i in 0..<AUTOTILE_COUNT {
            if g_autotile[c][i].tex.id != 0 { rl.UnloadTexture(g_autotile[c][i].tex) }
        }
    }
}


// ---------------------------------------------------------------------------
// Artist reference: a grid of the 47 blob configs, each cell a 3x3 connectivity
// diagram (filled center + connected neighbours) with its index. The artist draws one
// iso tile per index into data/sprites/tiles/<stem>_auto_NN.png.
// ---------------------------------------------------------------------------

autotile_export_reference :: proc() -> bool {
    COLS   :: 8
    ROWS   :: 6
    CELL   :: i32(128)
    PAD    :: i32(10)
    CW     := CELL + PAD

    W := i32(COLS) * CW + PAD
    H := i32(ROWS) * CW + PAD

    rt := rl.LoadRenderTexture(W, H)
    rl.BeginTextureMode(rt)
    rl.ClearBackground(rl.Color{ 24, 22, 28, 255 })

    for idx in 0..<AUTOTILE_COUNT {
        m  := g_blob47_mask[idx]
        cx := PAD + i32(idx % COLS) * CW
        cy := PAD + i32(idx / COLS) * CW

        rl.DrawRectangle(cx, cy, CELL, CELL, rl.Color{ 34, 32, 40, 255 })
        rl.DrawRectangleLines(cx, cy, CELL, CELL, rl.Color{ 70, 66, 84, 255 })

        // 3x3 connectivity diagram
        sub := CELL / 3
        fill := rl.Color{ 120, 180, 250, 255 }
        self := rl.Color{ 245, 210, 90, 255 }
        set  := proc(m, bit: int) -> bool { return m & bit != 0 }

        // (col,row) within the 3x3, and the bit that lights it
        cells := [9]struct{ c, r, bit: i32 }{
            { 1, 1, -1 },   // center = self
            { 1, 0, 1 },    // N
            { 2, 1, 2 },    // E
            { 1, 2, 4 },    // S
            { 0, 1, 8 },    // W
            { 2, 0, 16 },   // NE
            { 2, 2, 32 },   // SE
            { 0, 2, 64 },   // SW
            { 0, 0, 128 },  // NW
        }
        for cinfo in cells {
            x := cx + cinfo.c * sub + 3
            y := cy + cinfo.r * sub + 3
            sz := sub - 6
            if cinfo.bit < 0 {
                rl.DrawRectangle(x, y, sz, sz, self)
            } else if set(m, int(cinfo.bit)) {
                rl.DrawRectangle(x, y, sz, sz, fill)
            } else {
                rl.DrawRectangleLines(x, y, sz, sz, rl.Color{ 60, 56, 72, 255 })
            }
        }

        // index label
        lbl := fmt.ctprintf("%02d", idx)
        rl.DrawText(lbl, cx + 6, cy + 4, 18, rl.Color{ 235, 235, 240, 255 })
    }

    rl.EndTextureMode()

    img := rl.LoadImageFromTexture(rt.texture)
    rl.ImageFlipVertical(&img)
    ok := rl.ExportImage(img, "data/sprites/tiles/autotile_reference.png")
    rl.UnloadImage(img)
    rl.UnloadRenderTexture(rt)
    return ok
}
