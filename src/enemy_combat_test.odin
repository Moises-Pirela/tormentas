package main

import "core:testing"
import "core:math"

@(private = "file")
Arena :: struct {
    w:         World,
    tiles:     map[[2]int]TileType,
    doors:     map[[2]int]int,
    old_tiles: map[[2]int]TileType,
    old_doors: map[[2]int]int,
}

@(private = "file")
_arena_begin :: proc(a: ^Arena, cols: int) {
    a.w         = make_world()
    a.old_tiles = g_tilemap
    a.old_doors = g_door_blockers
    a.tiles     = make(map[[2]int]TileType)
    a.doors     = make(map[[2]int]int)
    for x in -1..<cols { for y in -1..=1 { a.tiles[{x, y}] = .Floor } }
    g_tilemap       = a.tiles
    g_door_blockers = a.doors
    ai_paths_init()
}

@(private = "file")
_arena_end :: proc(a: ^Arena) {
    ai_paths_destroy()
    g_tilemap       = a.old_tiles
    g_door_blockers = a.old_doors
    delete(a.tiles)
    delete(a.doors)
    destroy_world(&a.w)
}

@(private = "file")
_spawn_target :: proc(w: ^World, x, y: f32, faction: u8, radius: f32 = 14) -> int {
    id := world_create_entity(w)
    comp_set(w, id, .Transform, TransformComp{ position = { x, y, 0 } })
    comp_set(w, id, .Health, HealthComp{ current = 100, max = 100 })
    comp_set(w, id, .Collider, ColliderComp{ radius = radius, faction = faction })
    return id
}

@(private = "file")
_spawn_shot :: proc(w: ^World, from, to: [2]f32, faction: u8) -> int {
    id := world_create_entity(w)
    d  := to - from
    l  := math.sqrt(d[0]*d[0] + d[1]*d[1])
    comp_set(w, id, .Transform, TransformComp{ position = { to[0], to[1], 0 } })
    comp_set(w, id, .Projectile, ProjectileComp{
        direction = { d[0] / l, d[1] / l, 0 }, speed = l * f32(TICK_RATE), lifetime = 1,
        damage = 10, owner_id = INVALID_ENTITY, owner_faction = faction,
        prev_pos = from, has_prev = true,
    })
    comp_add(w, id, .ProjectileTag)
    return id
}

@(private = "file")
_damage_to :: proc(w: ^World, id: int) -> f32 {
    total := f32(0)
    for ev in w.damage_events { if ev.target_id == id { total += ev.amount } }
    return total
}

@(test)
fast_projectiles_hit_targets_they_pass_through_in_one_tick :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    e    := _spawn_target(&a.w, 300, 32, 1)
    shot := _spawn_shot(&a.w, { 100, 32 }, { 600, 32 }, 0)
    projectile_collision_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, e), f32(10))
    testing.expect(t, world_tag_is_destroy(&a.w, shot))
    px := comp_get(&a.w, shot, .Transform, TransformComp).position[0]
    testing.expectf(t, px < 300 && px > 250, "shot should stop at the target's edge, x=%v", px)
}

@(test)
projectile_hitbox_is_the_ground_circle :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    r    := projectile_hit_radius(14, 0)
    near := _spawn_target(&a.w, 300, 32 + r - 1, 1)
    far  := _spawn_target(&a.w, 400, 32 - r - 1, 1)
    _spawn_shot(&a.w, { 100, 32 }, { 600, 32 }, 0)
    comp_get(&a.w, near, .Collider, ColliderComp).faction = 1
    projectile_collision_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, near), f32(10))
    testing.expect_value(t, _damage_to(&a.w, far), f32(0))
}

@(test)
walls_and_closed_doors_stop_projectiles :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    a.tiles[{3, 0}] = .Wall1
    e    := _spawn_target(&a.w, 400, 32, 1)
    shot := _spawn_shot(&a.w, { 100, 32 }, { 600, 32 }, 0)
    projectile_collision_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, e), f32(0))
    testing.expect(t, world_tag_is_destroy(&a.w, shot))
    testing.expect(t, comp_get(&a.w, shot, .Transform, TransformComp).position[0] <= 192.01)

    a.tiles[{3, 0}] = .Floor
    g_door_blockers[{5, 0}] = 1
    a.doors = g_door_blockers
    clear(&a.w.damage_events)
    _spawn_shot(&a.w, { 100, 32 }, { 600, 32 }, 0)
    projectile_collision_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, e), f32(0))
}

@(test)
shots_pass_through_dodging_dead_and_friendly_targets :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    dodging := _spawn_target(&a.w, 200, 32, 0, 16)
    comp_set(&a.w, dodging, .DodgeState, DodgeComp{ active = true })
    dead := _spawn_target(&a.w, 280, 32, 0, 16)
    comp_get(&a.w, dead, .Health, HealthComp).current = 0
    ally   := _spawn_target(&a.w, 340, 32, 1)
    victim := _spawn_target(&a.w, 420, 32, 0, 16)
    _spawn_shot(&a.w, { 100, 32 }, { 600, 32 }, 1)
    projectile_collision_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, dodging), f32(0))
    testing.expect_value(t, _damage_to(&a.w, dead), f32(0))
    testing.expect_value(t, _damage_to(&a.w, ally), f32(0))
    testing.expect_value(t, _damage_to(&a.w, victim), f32(10))
}

@(private = "file")
_spawn_enemy :: proc(w: ^World, x: f32, kind: AIType, range: f32) -> int {
    id := world_create_entity(w)
    comp_set(w, id, .Transform, TransformComp{ position = { x, 32, 0 } })
    comp_set(w, id, .Velocity, VelocityComp{})
    comp_set(w, id, .AIAgent, AIAgentComp{
        state = AI_STATE_CHASE, attack_range = range, cooldown_max = 1,
        windup_max = 0.4, damage = 10, ai_type = kind, speed = 100,
        pellet_count = 1, spread_angle = 0.01, proj_speed = 600,
    })
    return id
}

@(private = "file")
_count :: proc(w: ^World, c: ComponentType) -> int {
    ids := world_query(w, query_mask(c))
    defer delete(ids)
    return len(ids)
}

@(private = "file")
_tick_ai :: proc(w: ^World, seconds: f32) {
    for _ in 0..<int(seconds * f32(TICK_RATE) + 0.5) { ai_system(w, .Update, TICK_DT) }
}

@(test)
melee_enemies_wind_up_then_strike_where_they_aimed :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    pid := _spawn_target(&a.w, 130, 32, 0, 16)
    a.w.player_ids[0] = pid
    a.w.player_id     = pid
    e := _spawn_enemy(&a.w, 100, .Melee, 44)

    _tick_ai(&a.w, TICK_DT)
    ai := comp_get(&a.w, e, .AIAgent, AIAgentComp)
    testing.expect(t, ai.windup > 0)
    testing.expect_value(t, _count(&a.w, .MeleeArc), 0)
    _tick_ai(&a.w, 0.3)
    testing.expect_value(t, _count(&a.w, .MeleeArc), 0)

    comp_get(&a.w, pid, .Transform, TransformComp).position = { 100, 120, 0 }
    _tick_ai(&a.w, 0.15)
    testing.expect_value(t, _count(&a.w, .MeleeArc), 1)
    arcs := world_query(&a.w, query_mask(.MeleeArc))
    defer delete(arcs)
    testing.expect(t, abs(comp_get(&a.w, arcs[0], .MeleeArc, MeleeArcComp).angle) < 0.001)
    melee_arc_system(&a.w, .Update, TICK_DT)
    testing.expect_value(t, _damage_to(&a.w, pid), f32(0))
}

@(test)
stun_cancels_a_windup :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    pid := _spawn_target(&a.w, 130, 32, 0, 16)
    a.w.player_ids[0] = pid
    a.w.player_id     = pid
    e := _spawn_enemy(&a.w, 100, .Melee, 44)
    _tick_ai(&a.w, 0.1)
    status_effect_apply(&a.w, e, StatusEffect{ type = .Stun, duration = 1 })
    _tick_ai(&a.w, 0.5)
    testing.expect_value(t, comp_get(&a.w, e, .AIAgent, AIAgentComp).windup, f32(0))
    testing.expect_value(t, _count(&a.w, .MeleeArc), 0)
}

@(test)
ranged_enemies_need_line_of_sight_and_reach_their_range :: proc(t: ^testing.T) {
    a: Arena
    _arena_begin(&a, 12)
    defer _arena_end(&a)
    pid := _spawn_target(&a.w, 500, 32, 0, 16)
    a.w.player_ids[0] = pid
    a.w.player_id     = pid
    a.tiles[{4, 0}] = .Wall1
    e := _spawn_enemy(&a.w, 100, .Ranged, 544)
    _tick_ai(&a.w, TICK_DT)
    testing.expect_value(t, comp_get(&a.w, e, .AIAgent, AIAgentComp).windup, f32(0))

    a.tiles[{4, 0}] = .Floor
    comp_get(&a.w, e, .Transform, TransformComp).position = { 100, 32, 0 }
    _tick_ai(&a.w, TICK_DT)
    testing.expect(t, comp_get(&a.w, e, .AIAgent, AIAgentComp).windup > 0)
    _tick_ai(&a.w, 0.45)
    testing.expect_value(t, _count(&a.w, .Projectile), 1)

    speed, life := ai_projectile_reach(comp_get(&a.w, e, .AIAgent, AIAgentComp)^)
    testing.expect(t, speed * life >= 544)
}

@(test)
health_bars_appear_on_hit_fade_later_and_show_on_hover :: proc(t: ^testing.T) {
    st: HpBarState
    hpbar_step(&st, 1, 0.016)
    testing.expect_value(t, hpbar_alpha(st.since_hit, false, false), f32(0))
    testing.expect_value(t, hpbar_alpha(st.since_hit, true, false), f32(1))

    hpbar_step(&st, 0.6, 0.016)
    testing.expect_value(t, hpbar_alpha(st.since_hit, false, false), f32(1))
    testing.expect_value(t, st.chip_frac, f32(1))

    for _ in 0..<60 { hpbar_step(&st, 0.6, 1.0 / 60) }
    testing.expect_value(t, st.chip_frac, f32(0.6))
    testing.expect_value(t, hpbar_alpha(st.since_hit, false, false), f32(1))

    for _ in 0..<int((HPBAR_HOLD + HPBAR_FADE) * 60) + 2 { hpbar_step(&st, 0.6, 1.0 / 60) }
    testing.expect(t, hpbar_alpha(st.since_hit, false, false) <= 0.01)
    testing.expect_value(t, hpbar_alpha(st.since_hit, false, true), f32(1))
}
