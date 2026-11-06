package main

import "core:testing"

@(private = "file")
BrushFixture :: struct {
    tiles, old_tiles:     map[[2]int]TileType,
    overlay, old_overlay: map[[2]int]TileOverlay,
    brush:                EditorBrush,
    size:                 int,
    tool:                 EditorTool,
    hub:                  bool,
}

@(private = "file")
_begin :: proc(f: ^BrushFixture, brush: EditorBrush, size := TILE_SIZE) {
    f.old_tiles, f.old_overlay = g_tilemap, g_overlay_map
    f.tiles   = make(map[[2]int]TileType)
    f.overlay = make(map[[2]int]TileOverlay)
    g_tilemap, g_overlay_map = f.tiles, f.overlay
    f.brush, f.size, f.tool, f.hub = g_ed_brush, g_ed_brush_size, g_ed_tool, g_hub_active
    g_ed_brush, g_ed_brush_size, g_ed_tool, g_hub_active = brush, size, .Paint, false
}

@(private = "file")
_end :: proc(f: ^BrushFixture) {
    ed_stroke_destroy()
    delete(g_tilemap)
    delete(g_overlay_map)
    g_tilemap, g_overlay_map = f.old_tiles, f.old_overlay
    g_ed_brush, g_ed_brush_size, g_ed_tool, g_hub_active = f.brush, f.size, f.tool, f.hub
}

@(test)
fast_strokes_paint_every_cell_between_frames :: proc(t: ^testing.T) {
    f: BrushFixture
    _begin(&f, .Wall)
    defer _end(&f)
    ed_stroke_begin(.Paint, .LEFT)
    ed_stroke_update({ 0, 0 })
    ed_stroke_update({ 10, 4 })
    ed_stroke_end()
    testing.expect_value(t, g_ed_stroke.applied, 11)
    for x in 0..=10 {
        found := false
        for y in 0..=4 { if tile_at(x, y) == .Wall && tile_exists(x, y) { found = true } }
        testing.expectf(t, found, "column %d has no painted tile", x)
    }
}

@(test)
holding_still_or_repainting_applies_nothing :: proc(t: ^testing.T) {
    f: BrushFixture
    _begin(&f, .Wall, TILE_SIZE * 3)
    defer _end(&f)
    ed_stroke_begin(.Paint, .LEFT)
    for _ in 0..<30 { ed_stroke_update({ 5, 5 }) }
    testing.expect_value(t, g_ed_stroke.applied, 9)
    ed_stroke_end()

    g_wall_mask_dirty = false
    ed_stroke_begin(.Paint, .LEFT)
    ed_stroke_update({ 5, 5 })
    ed_stroke_end()
    testing.expect_value(t, g_ed_stroke.applied, 0)
    testing.expect(t, !g_wall_mask_dirty)
}

@(test)
overlapping_footprints_touch_each_tile_once :: proc(t: ^testing.T) {
    f: BrushFixture
    _begin(&f, .Oil, TILE_SIZE * 3)
    defer _end(&f)
    ed_stroke_begin(.Paint, .LEFT)
    ed_stroke_update({ 0, 0 })
    ed_stroke_update({ 3, 0 })
    ed_stroke_end()
    testing.expect_value(t, g_ed_stroke.applied, 18)
    testing.expect_value(t, len(g_tilemap), 18)
    testing.expect_value(t, overlay_at(1, 1), TileOverlay.Oil)
}

@(test)
brush_footprint_matches_the_displayed_size :: proc(t: ^testing.T) {
    saved := g_ed_brush_size
    defer g_ed_brush_size = saved
    for n in 1..=6 {
        g_ed_brush_size = TILE_SIZE * n
        _, _, a := ed_brush_footprint(10, 10, TILE_SIZE, false)
        _, _, b := ed_brush_footprint(10, 10, TILE_SIZE, true)
        testing.expect_value(t, a, n)
        testing.expect_value(t, b, n)
    }
    g_ed_brush_size = TILE_SIZE * 4
    x0, y0, _ := ed_brush_footprint(10, 10, TILE_SIZE, false)
    testing.expect(t, x0 <= 10 && x0 + 4 > 10 && y0 <= 10 && y0 + 4 > 10)
}

@(test)
erase_strokes_only_touch_tiles_with_content :: proc(t: ^testing.T) {
    f: BrushFixture
    _begin(&f, .Floor)
    defer _end(&f)
    g_tilemap[{ 2, 0 }] = .Floor
    g_tilemap[{ 4, 0 }] = .Wall
    ed_stroke_begin(.Erase, .LEFT)
    ed_stroke_update({ 0, 0 })
    ed_stroke_update({ 6, 0 })
    ed_stroke_end()
    testing.expect_value(t, g_ed_stroke.applied, 2)
    testing.expect_value(t, len(g_tilemap), 0)
}
