package main

import "core:testing"
import "core:strings"
import "core:encoding/json"

@(private = "file")
_test_target :: proc(w: ^World, hp: f32) -> int {
    id := world_create_entity(w)
    comp_set(w, id, .Health, HealthComp{ current = hp, max = hp })
    return id
}

@(test)
physical_armor_and_resist_share_one_mitigation_cap :: proc(t: ^testing.T) {
    w := make_world()
    defer destroy_world(&w)
    id := _test_target(&w, 1000)
    comp_set(&w, id, .Stats, StatsComp{ armor = 0.75 })
    comp_set(&w, id, .Resistance, ResistanceComp{ physical = 0.75 })
    world_push_damage(&w, id, 100)
    damage_system(&w, .LateUpdate, TICK_DT)
    hp := comp_get(&w, id, .Health, HealthComp).current
    testing.expectf(t, abs(hp - 975) < 0.01, "expected 25 damage after the 75%% cap, hp=%v", hp)
}

@(test)
dead_targets_ignore_damage_and_heals :: proc(t: ^testing.T) {
    w := make_world()
    defer destroy_world(&w)
    id := _test_target(&w, 50)
    comp_get(&w, id, .Health, HealthComp).current = 0
    world_push_damage(&w, id, 30)
    world_push_heal(&w, id, 30)
    damage_system(&w, .LateUpdate, TICK_DT)
    testing.expect_value(t, comp_get(&w, id, .Health, HealthComp).current, f32(0))
}

@(test)
dodging_targets_take_no_damage :: proc(t: ^testing.T) {
    w := make_world()
    defer destroy_world(&w)
    id := _test_target(&w, 100)
    comp_set(&w, id, .DodgeState, DodgeComp{ active = true })
    world_push_damage(&w, id, 40)
    damage_system(&w, .LateUpdate, TICK_DT)
    testing.expect_value(t, comp_get(&w, id, .Health, HealthComp).current, f32(100))
    comp_get(&w, id, .DodgeState, DodgeComp).active = false
    world_push_damage(&w, id, 40)
    damage_system(&w, .LateUpdate, TICK_DT)
    testing.expect_value(t, comp_get(&w, id, .Health, HealthComp).current, f32(60))
}

@(test)
self_heals_bypass_the_targets_own_heal_blocks :: proc(t: ^testing.T) {
    w := make_world()
    defer destroy_world(&w)
    id := _test_target(&w, 100)
    comp_get(&w, id, .Health, HealthComp).current = 50
    comp_set(&w, id, .Stats, StatsComp{ healing_blocked = true, pickup_healing_blocked = true })
    world_push_heal(&w, id, 20)
    damage_system(&w, .LateUpdate, TICK_DT)
    testing.expect_value(t, comp_get(&w, id, .Health, HealthComp).current, f32(50))
    world_push_self_heal(&w, id, 20)
    damage_system(&w, .LateUpdate, TICK_DT)
    testing.expect_value(t, comp_get(&w, id, .Health, HealthComp).current, f32(70))
}

@(private = "file")
_poison_damage_over :: proc(max_hp, strength, seconds: f32) -> f32 {
    w := make_world()
    defer destroy_world(&w)
    id := _test_target(&w, max_hp)
    comp_add(&w, id, .Organic)
    status_effect_apply(&w, id, StatusEffect{
        type = .Poison, application = .Base, stack_behavior = .Refresh,
        duration = seconds + 1, strength = strength,
    })
    total := f32(0)
    for _ in 0..<int(seconds * f32(TICK_RATE)) {
        status_effect_system(&w, .Update, TICK_DT)
        for ev in w.damage_events { total += ev.amount }
        clear(&w.damage_events)
    }
    return total
}

@(test)
poison_scales_with_max_hp_and_has_a_floor :: proc(t: ^testing.T) {
    boss := _poison_damage_over(1400, 1.0, 5)
    testing.expectf(t, boss >= 270 && boss <= 281, "boss took %v over 5s, expected ~280 (4%%/s)", boss)
    small := _poison_damage_over(30, 1.0, 5)
    testing.expectf(t, small >= 29 && small <= 30, "30hp enemy took %v over 5s, expected the 6/s floor", small)
    capped := _poison_damage_over(1400, 50.0, 1)
    testing.expectf(t, capped <= 168.5, "potency must clamp at %v, got %v", POISON_MAX_POTENCY, capped)
}

@(test)
rebinding_a_used_key_swaps_instead_of_duplicating :: proc(t: ^testing.T) {
    saved := g_binds
    defer g_binds = saved
    g_binds = default_binds()
    rows := all_bind_rows()
    old_dodge := g_binds.gameplay.dodge
    skill1_idx := -1
    for r, i in rows { if r.ptr == &g_binds.gameplay.skill1 { skill1_idx = i } }
    testing.expect(t, skill1_idx >= 0)
    bind_assign_unique(&rows, skill1_idx, old_dodge)
    testing.expect_value(t, g_binds.gameplay.skill1, old_dodge)
    testing.expect_value(t, g_binds.gameplay.dodge, saved_skill1_default())
    seen: map[i32]int
    defer delete(seen)
    for r in rows[:GAMEPLAY_BIND_COUNT] {
        if r.ptr^ == 0 { continue }
        seen[r.ptr^] += 1
        testing.expectf(t, seen[r.ptr^] == 1, "duplicate gameplay binding %v", r.ptr^)
    }
}

@(private = "file")
saved_skill1_default :: proc() -> i32 { return default_binds().gameplay.skill1 }

@(test)
user_files_live_outside_the_app_bundle_on_macos :: proc(t: ^testing.T) {
    saved := g_user_dir
    defer g_user_dir = saved
    g_user_dir = ""
    dir := user_data_dir()
    when ODIN_OS == .Darwin {
        testing.expectf(t, strings.has_suffix(dir, "Library/Application Support/Tormentas"), "user dir %v", dir)
    } else {
        testing.expect_value(t, dir, ".")
    }
    testing.expect(t, strings.has_suffix(user_path("save/characters.bin"), "save/characters.bin"))
    delete(g_user_dir)
}

@(test)
display_settings_survive_a_config_round_trip :: proc(t: ^testing.T) {
    saved := g_binds
    defer g_binds = saved
    g_binds = default_binds()
    g_binds.display = { mode = WINDOW_MODE_WINDOW, window_w = 1280, window_h = 720 }
    data, err := json.marshal(g_binds, allocator = context.temp_allocator)
    testing.expect(t, err == nil)
    back := default_binds()
    testing.expect(t, json.unmarshal(data, &back, allocator = context.temp_allocator) == nil)
    testing.expect_value(t, back.display.mode, WINDOW_MODE_WINDOW)
    testing.expect_value(t, back.display.window_w, i32(1280))
    when ODIN_OS == .Darwin {
        testing.expect(t, platform_default_fullscreen())
    }
}
