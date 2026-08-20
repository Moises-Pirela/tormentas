package main

import "core:math"

AI_PATH_MAX    :: 64
AI_PATH_RETICK :: f32(0.35)

SQRT2 :: f32(1.41421356)

AIPath :: struct {
    path:    [AI_PATH_MAX][2]int,
    len:     int,
    idx:     int,
    timer:   f32,
    goal:    [2]int,
}

@(private="file")
g_ai_paths: map[int]AIPath

ai_paths_init    :: proc() { g_ai_paths = make(map[int]AIPath) }
ai_paths_destroy :: proc() { delete(g_ai_paths) }
ai_paths_clear   :: proc() { clear(&g_ai_paths) }

ai_navigate :: proc(id: int, pos, target_pos: [2]f32, dt: f32) -> [2]f32 {
    sx, sy := world_to_tile(pos[0],        pos[1])
    gx, gy := world_to_tile(target_pos[0], target_pos[1])
    start  := [2]int{ sx, sy }
    goal   := [2]int{ gx, gy }

    if start == goal { return {0, 0} }

    if id not_in g_ai_paths { g_ai_paths[id] = AIPath{} }
    p := &g_ai_paths[id]

    p.timer -= dt
    if p.timer <= 0 || p.goal != goal || p.len == 0 {
        p.timer = AI_PATH_RETICK
        p.goal  = goal
        p.len   = _astar(start, goal, &p.path)
        p.idx   = 0
    }

    if p.len == 0 || p.idx >= p.len {
        return {0, 0}
    }

    WAYPOINT_RADIUS :: f32(TILE_SIZE) * 0.55
    for p.idx < p.len {
        wp := _tile_center(p.path[p.idx])
        dx := wp[0] - pos[0]
        dy := wp[1] - pos[1]
        if dx*dx + dy*dy > WAYPOINT_RADIUS*WAYPOINT_RADIUS { break }
        p.idx += 1
    }

    if p.idx >= p.len { return {0, 0} }

    wp := _tile_center(p.path[p.idx])
    dx := wp[0] - pos[0]
    dy := wp[1] - pos[1]
    d  := math.sqrt(dx*dx + dy*dy)
    if d < 0.5 { return {0, 0} }
    return { dx / d, dy / d }
}

@(private="file")
_tile_center :: proc(t: [2]int) -> [2]f32 {
    return {
        f32(t[0]) * TILE_SIZE + TILE_SIZE * 0.5,
        f32(t[1]) * TILE_SIZE + TILE_SIZE * 0.5,
    }
}

@(private="file")
_octile :: proc(a, b: [2]int) -> f32 {
    dx := abs(b[0] - a[0])
    dy := abs(b[1] - a[1])
    mn := min(dx, dy)
    mx := max(dx, dy)
    return f32(mx - mn) + SQRT2 * f32(mn)
}

@(private="file")
AStarNode :: struct {
    pos: [2]int,
    f:   f32,
}

@(private="file")
_heap_push :: proc(h: ^[dynamic]AStarNode, n: AStarNode) {
    append(h, n)
    i := len(h) - 1
    for i > 0 {
        p := (i - 1) / 2
        if h[p].f <= h[i].f { break }
        h[p], h[i] = h[i], h[p]
        i = p
    }
}

@(private="file")
_heap_pop :: proc(h: ^[dynamic]AStarNode) -> AStarNode {
    top  := h[0]
    last := len(h) - 1
    h[0]  = h[last]
    resize(h, last)
    i := 0
    for {
        l, r, s := 2*i+1, 2*i+2, i
        if l < len(h) && h[l].f < h[s].f { s = l }
        if r < len(h) && h[r].f < h[s].f { s = r }
        if s == i { break }
        h[i], h[s] = h[s], h[i]
        i = s
    }
    return top
}

@(private="file")
DIRS :: [8][2]int{
    {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

@(private="file")
_astar :: proc(start, goal: [2]int, out: ^[AI_PATH_MAX][2]int) -> int {
    if !tile_is_walkable(goal[0], goal[1])  { return 0 }
    if !tile_is_walkable(start[0], start[1]) { return 0 }
    if start == goal                         { return 0 }

    open   := make([dynamic]AStarNode)
    g_map  := make(map[[2]int]f32)
    came   := make(map[[2]int][2]int)
    closed := make(map[[2]int]bool)
    defer { delete(open); delete(g_map); delete(came); delete(closed) }

    g_map[start] = 0
    _heap_push(&open, AStarNode{ pos = start, f = _octile(start, goal) })

    MAX_ITER :: 1024
    iter     := 0
    found    := false

    for len(open) > 0 && iter < MAX_ITER {
        iter += 1
        cur := _heap_pop(&open)
        if cur.pos == goal { found = true; break }
        if closed[cur.pos] { continue }
        closed[cur.pos] = true

        g_cur := g_map[cur.pos]

        for dir in DIRS {
            nb := [2]int{ cur.pos[0] + dir[0], cur.pos[1] + dir[1] }
            if closed[nb] { continue }
            if !tile_is_walkable(nb[0], nb[1]) { continue }

            if dir[0] != 0 && dir[1] != 0 {
                if !tile_is_walkable(cur.pos[0]+dir[0], cur.pos[1]) ||
                   !tile_is_walkable(cur.pos[0], cur.pos[1]+dir[1]) {
                    continue
                }
            }

            step_cost := SQRT2 if (dir[0] != 0 && dir[1] != 0) else f32(1)
            tg        := g_cur + step_cost
            prev, has := g_map[nb]
            if !has || tg < prev {
                g_map[nb] = tg
                came[nb]  = cur.pos
                _heap_push(&open, AStarNode{ pos = nb, f = tg + _octile(nb, goal) })
            }
        }
    }

    if !found { return 0 }

    temp: [AI_PATH_MAX][2]int
    n := 0
    c := goal
    for c != start && n < AI_PATH_MAX {
        temp[n] = c
        n += 1
        p, ok := came[c]
        if !ok { return 0 }
        c = p
    }
    for i in 0..<n {
        out[i] = temp[n - 1 - i]
    }
    return n
}
