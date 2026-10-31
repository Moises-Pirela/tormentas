package main

import "core:testing"
import "core:math"

@(test)
projection_round_trip_preserves_negative_and_fractional_coordinates :: proc(t: ^testing.T) {
    for point in ([][2]f32{{0, 0}, {100, -50}, {-128, -64}, {0.25, -0.75}, {10000, 10000}}) {
        iso := world_to_iso_xy(point[0], point[1])
        world := iso_to_world_xy(iso.x, iso.y)
        testing.expect(t, abs(world.x - point[0]) < 0.001 && abs(world.y - point[1]) < 0.001)
    }
}

@(test)
movement_preserves_screen_speed_in_all_eight_directions :: proc(t: ^testing.T) {
    for input in ([][2]f32{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}) {
        length := math.sqrt(input[0]*input[0] + input[1]*input[1])
        screen := input / length
        world := screen_dir_to_world_dir(screen)
        projected := world_to_iso_xy(world[0], world[1])
        testing.expect(t, abs(projected.x - screen[0]) < 0.0001 && abs(projected.y - screen[1]) < 0.0001)
    }
    testing.expect(t, screen_dir_to_world_dir({0, 0}) == [2]f32{})
}

@(test)
navigation_respects_blockers_and_cannot_cut_corners :: proc(t: ^testing.T) {
    previous := g_tilemap
    g_tilemap = make(map[[2]int]TileType)
    defer { delete(g_tilemap); g_tilemap = previous }
    ai_paths_init()
    defer ai_paths_destroy()
    size := f32(TILE_SIZE)
    start := [2]f32{size * 0.5, size * 0.5}
    target := [2]f32{size * 1.5, size * 1.5}
    g_tilemap[{0, 0}] = .Floor
    g_tilemap[{1, 1}] = .Floor
    testing.expect(t, ai_navigate(1, start, target, 0) == [2]f32{})
    g_tilemap[{1, 0}] = .Floor
    ai_paths_clear()
    direction := ai_navigate(1, start, target, 0)
    testing.expect(t, direction[0] > 0 && abs(direction[1]) < 0.0001)
    g_tilemap[{1, 1}] = .Wall
    ai_paths_clear()
    testing.expect(t, ai_navigate(1, start, target, 0) == [2]f32{})
    testing.expect(t, ai_navigate(1, start, start, 0) == [2]f32{})
}
