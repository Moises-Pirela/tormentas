package main

import "core:math/rand"

DIRECTOR_MIN_DIST   :: f32(380)
BOSS_MIN_DIST       :: f32(520)
BOSS_WARNING_LEAD   :: f32(18.0)
DIRECTOR_BUDGET_CAP :: f32(24.0)

MAX_DIRECTOR_LEVELS :: 3

DirectorConfig :: struct {
    budget_rate:    f32,
    max_alive:      int,
    spawn_interval: f32,
    has_boss:       bool,
    boss_spawn_at:  f32,
}

DIRECTOR_CONFIGS := [MAX_DIRECTOR_LEVELS + 1]DirectorConfig{
    0 = {},
    1 = { budget_rate = 2.00, max_alive = 100, spawn_interval = 1.0, has_boss = true, boss_spawn_at = RAID_TIME * 0.50 },
    2 = { budget_rate = 0.85, max_alive = 100, spawn_interval = 1.0, has_boss = true,  boss_spawn_at = RAID_TIME * 0.60 },
    3 = { budget_rate = 1.25, max_alive = 100, spawn_interval = 1.0, has_boss = true,  boss_spawn_at = RAID_TIME * 0.72 },
}

DirectorEnemy :: struct {
    name: string,
    cost: f32,
}

DIRECTOR_ROSTER := [?]DirectorEnemy{
    { "enemy_spider", 1 },
}

ENEMY_MUTATION_POOL :: [?]MutationType{
    .LivingBomb,
    .ToxicFlesh,
    .ThornPact,
    .BlackLung,
}

TIER_RARE_CHANCE      :: f32(0.22)
TIER_LEGENDARY_CHANCE :: f32(0.05)

SpawnDirector :: struct {
    budget:       f32,
    spawn_cd:     f32,
    boss_spawned: bool,
}

g_director:           SpawnDirector
g_boss_id:            int = INVALID_ENTITY
g_boss_warning_timer: f32

director_init :: proc() {
    g_director           = {}
    g_boss_id            = INVALID_ENTITY
    g_boss_warning_timer = 0
}

spawn_director_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update              { return }
    if g_hub_active                  { return }
    if g_playing_state != .Gameplay  { return }
    if g_raid_timer <= 0             { return }

    cfg_idx := clamp(g_current_raid_level, 0, MAX_DIRECTOR_LEVELS)
    cfg     := DIRECTOR_CONFIGS[cfg_idx]
    if cfg.budget_rate <= 0 { return }

    _director_tick_boss(w, cfg, dt)
    _director_tick_spawns(w, cfg, dt)
}

@(private = "file")
_director_apply_tier :: proc(w: ^World, id: int) {
    if id == INVALID_ENTITY                          { return }
    if !world_has_component(w, id, .AIAgent)         { return }

    rng_state := rand.create(u64(w.tick) ~ (u64(id) * 0x9e3779b97f4a7c15))
    context.random_generator = rand.default_random_generator(&rng_state)

    r    := rand.float32()
    tier := EnemyTier.Normal
    mut_count := 0

    if r < TIER_LEGENDARY_CHANCE {
        tier      = .Legendary
        mut_count = rand.int_max(3) + 3
    } else if r < TIER_LEGENDARY_CHANCE + TIER_RARE_CHANCE {
        tier      = .Rare
        mut_count = rand.int_max(2) + 1
    }

    comp_get(w, id, .AIAgent, AIAgentComp).tier = tier

    if mut_count == 0 { return }

    if !world_has_component(w, id, .MutationContainer) {
        comp_set(w, id, .MutationContainer, mutation_container_empty())
    }

    pool    := ENEMY_MUTATION_POOL
    picked  : [len(ENEMY_MUTATION_POOL)]MutationType
    n_picked := 0
    attempts := 0
    for n_picked < mut_count && attempts < 20 {
        attempts += 1
        mt := pool[rand.int_max(len(pool))]
        dup := false
        for i in 0..<n_picked { if picked[i] == mt { dup = true; break } }
        if dup { continue }
        picked[n_picked] = mt
        n_picked += 1
        mutation_restore_direct(w, id, mt)
    }
}

@(private = "file")
_director_tick_boss :: proc(w: ^World, cfg: DirectorConfig, dt: f32) {
    if !cfg.has_boss || g_director.boss_spawned { return }

    warning_start := cfg.boss_spawn_at + BOSS_WARNING_LEAD
    if g_raid_timer <= warning_start && g_boss_warning_timer <= 0 {
        g_boss_warning_timer = BOSS_WARNING_LEAD
        audio_duck_music(0.5, 500, 1200)
    }

    if g_boss_warning_timer > 0 {
        g_boss_warning_timer -= dt
    }

    if g_raid_timer <= cfg.boss_spawn_at {
        rng_state := rand.create(u64(w.tick) ~ 0xcafebabe87654321)
        context.random_generator = rand.default_random_generator(&rng_state)
        _director_spawn_boss(w)
        g_director.boss_spawned = true
        g_boss_warning_timer    = 0
    }
}

@(private = "file")
_director_tick_spawns :: proc(w: ^World, cfg: DirectorConfig, dt: f32) {
    if g_director.spawn_cd > 0 {
        g_director.spawn_cd -= dt
    }

    elapsed_frac := 1.0 - clamp(g_raid_timer / RAID_TIME, 0, 1)
    pressure     := f32(1.0) + elapsed_frac * 2.5
    g_director.budget = min(
        g_director.budget + cfg.budget_rate * pressure * dt,
        DIRECTOR_BUDGET_CAP,
    )

    if g_director.spawn_cd > 0 { return }

    alive_ids := world_query(w, query_mask(.AIAgent))
    alive     := len(alive_ids)
    delete(alive_ids)
    if alive >= cfg.max_alive { return }

    rng_state := rand.create(u64(w.tick) ~ 0xdeadbeef12345678)
    context.random_generator = rand.default_random_generator(&rng_state)

    affordable: [len(DIRECTOR_ROSTER)]int
    n_affordable := 0
    for i in 0..<len(DIRECTOR_ROSTER) {
        if DIRECTOR_ROSTER[i].cost <= g_director.budget {
            affordable[n_affordable] = i
            n_affordable += 1
        }
    }
    if n_affordable == 0 { return }

    chosen_idx := affordable[rand.int_max(n_affordable)]
    chosen     := DIRECTOR_ROSTER[chosen_idx]

    wx, wy, ok := _director_pick_anchor(w)
    if !ok { return }

    id := _director_spawn_enemy(w, chosen.name, wx, wy)
    if id == INVALID_ENTITY { return }

    if world_has_component(w, id, .AIAgent) {
        comp_get(w, id, .AIAgent, AIAgentComp).roster_index = u8(chosen_idx)
    }

    g_director.budget  -= chosen.cost
    g_director.spawn_cd = cfg.spawn_interval
}

@(private = "file")
_min_player_dist2 :: proc(w: ^World, x, y: f32) -> f32 {
    best := max(f32)
    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid)                  { continue }
        if !world_has_component(w, pid, .Transform) { continue }
        p  := comp_get(w, pid, .Transform, TransformComp).position
        dx := x - p[0]
        dy := y - p[1]
        d2 := dx*dx + dy*dy
        if d2 < best { best = d2 }
    }
    return best
}

@(private = "file")
_director_pick_anchor :: proc(w: ^World) -> (wx, wy: f32, ok: bool) {
    min_d2 := DIRECTOR_MIN_DIST * DIRECTOR_MIN_DIST

    anchor_ids := world_query(w, query_mask(.SpawnAnchor, .Transform))
    anchors := make([dynamic][2]f32, 0, len(anchor_ids), context.temp_allocator)
    defer delete(anchor_ids)
    for id in anchor_ids {
        p := comp_get(w, id, .Transform, TransformComp).position
        append(&anchors, [2]f32{p[0], p[1]})
    }

    if len(anchors) > 0 {
        n       := len(anchors)
        indices := make([]int, n, context.temp_allocator)
        for i in 0..<n { indices[i] = i }
        for i := n - 1; i > 0; i -= 1 {
            j := rand.int_max(i + 1)
            indices[i], indices[j] = indices[j], indices[i]
        }

        best_x, best_y := f32(0), f32(0)
        best_d2 := f32(-1)

        for idx in indices {
            spx := anchors[idx][0]
            spy := anchors[idx][1]
            d2  := _min_player_dist2(w, spx, spy)
            if d2 >= min_d2 {
                return spx, spy, true
            }
            if d2 > best_d2 {
                best_d2 = d2
                best_x  = spx
                best_y  = spy
            }
        }

        return best_x, best_y, best_d2 >= 0
    }

    candidates: [dynamic][2]int
    defer delete(candidates)
    for pos, tt in g_tilemap {
        if tile_base(tt) != .Floor { continue }
        cx := f32(pos[0]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
        cy := f32(pos[1]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
        if _min_player_dist2(w, cx, cy) >= min_d2 {
            append(&candidates, pos)
        }
    }
    if len(candidates) == 0 { return 0, 0, false }
    chosen := candidates[rand.int_max(len(candidates))]
    return f32(chosen[0]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5,
           f32(chosen[1]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5,
           true
}

@(private = "file")
_director_spawn_boss :: proc(w: ^World) {
    wx, wy, ok := _find_boss_tile(w)
    if !ok { return }

    id := spawn_from_def(w, find_entity_def(g_entity_defs, "enemy_boss"))
    if id == INVALID_ENTITY { return }

    comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
    g_boss_id = id
    _director_apply_tier(w, id)

    camera_shake(1.0)
    play_sfx("levelup")
}

@(private = "file")
_find_boss_tile :: proc(w: ^World) -> (wx, wy: f32, ok: bool) {
    candidates: [dynamic][2]int
    defer delete(candidates)

    for pos, tt in g_tilemap {
        if tile_base(tt) != .Floor { continue }
        if !_tile_open_3x3(pos[0], pos[1]) { continue }
        cx := f32(pos[0]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
        cy := f32(pos[1]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
        if _min_player_dist2(w, cx, cy) >= BOSS_MIN_DIST * BOSS_MIN_DIST {
            append(&candidates, pos)
        }
    }

    if len(candidates) == 0 { return 0, 0, false }

    chosen := candidates[rand.int_max(len(candidates))]
    wx = f32(chosen[0]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
    wy = f32(chosen[1]) * f32(TILE_SIZE) + f32(TILE_SIZE) * 0.5
    return wx, wy, true
}

@(private = "file")
_tile_open_3x3 :: proc(tx, ty: int) -> bool {
    for dy in -1..=1 {
        for dx in -1..=1 {
            if tile_base(tile_at(tx + dx, ty + dy)) != .Floor { return false }
        }
    }
    return true
}

@(private = "file")
_director_spawn_enemy :: proc(w: ^World, name: string, wx, wy: f32) -> int {
    id := spawn_from_def(w, find_entity_def(g_entity_defs, name))
    if id != INVALID_ENTITY && world_has_component(w, id, .Transform) {
        comp_get(w, id, .Transform, TransformComp).position = {wx, wy, 0}
    }
    _director_apply_tier(w, id)
    return id
}
