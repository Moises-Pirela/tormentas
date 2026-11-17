package sim

import "core:testing"

@(private = "file")
_test_sim :: proc() -> Simulation {
    s := make_simulation()
    s.role  = .Host
    s.state = .Running
    sim_register_system(&s, {.Update}, movement_system,      .Shared)
    sim_register_system(&s, {.Update}, self_destruct_system, .HostOnly)
    return s
}

@(private = "file")
_spawn_mover :: proc(w: ^World, pos, vel: [3]f32) -> int {
    id := world_create_entity(w)
    comp_set(w, id, .Transform, TransformComp{ position = pos })
    comp_set(w, id, .Velocity,  VelocityComp{ value = vel })
    return id
}

@(test)
movement_integrates_velocity :: proc(t: ^testing.T) {
    s := _test_sim()
    defer destroy_simulation(&s)
    id := _spawn_mover(&s.world, {10, 20, 0}, {60, -30, 0})

    for _ in 0 ..< 60 { sim_tick(&s, 1.0 / 60.0) }

    p := comp_get(&s.world, id, .Transform, TransformComp).position
    testing.expect(t, abs(p[0] - 70) < 0.01 && abs(p[1] - (-10)) < 0.01, "one second at (60,-30) from (10,20)")
}

@(test)
movement_skips_dead_players :: proc(t: ^testing.T) {
    s := _test_sim()
    defer destroy_simulation(&s)
    id := _spawn_mover(&s.world, {0, 0, 0}, {100, 0, 0})
    comp_set(&s.world, id, .Health, HealthComp{ current = 0, max = 100 })
    s.world.player_ids[0] = id

    testing.expect(t, is_player_entity(&s.world, id), "registered as a player")
    testing.expect(t, player_is_dead(&s.world, id),   "0 hp is dead")
    testing.expect_value(t, player_slot_for_id(&s.world, id), 0)

    for _ in 0 ..< 30 { sim_tick(&s, 1.0 / 60.0) }
    testing.expect_value(t, comp_get(&s.world, id, .Transform, TransformComp).position[0], 0)
}

@(test)
respawning_player_counts_as_dead :: proc(t: ^testing.T) {
    s := _test_sim()
    defer destroy_simulation(&s)
    id := _spawn_mover(&s.world, {0, 0, 0}, {0, 0, 0})
    comp_set(&s.world, id, .Health,  HealthComp{ current = 50, max = 100 })
    comp_set(&s.world, id, .Respawn, RespawnComp{ timer = 1.5 })
    testing.expect(t, player_is_dead(&s.world, id), "respawn timer running means dead")
}

@(private = "file")
_self_destruct_visible :: proc(w: ^World) -> int {
    q := world_query(w, query_mask(.SelfDestruct))
    defer delete(q)
    return len(q)
}

// Asserts the contract gameplay relies on today: expired entities drop out of queries, on the host
// only. It deliberately does NOT assert the slot is freed, because it isn't: world_tag_destroy sets
// .ToDestroy itself, so clockwork's world_mark_destroy early-returns and the id never reaches
// pending_destroy. Known leak, tracked in docs/BUILD_PLAN.md (P0). When it is fixed, add
// `!world_is_valid(&host.world, hid)` below.
@(test)
self_destruct_expires_on_host_only :: proc(t: ^testing.T) {
    host := _test_sim()
    defer destroy_simulation(&host)
    hid := world_create_entity(&host.world)
    comp_set(&host.world, hid, .SelfDestruct, SelfDestructComp{ timer = 0.25 })
    testing.expect_value(t, _self_destruct_visible(&host.world), 1)
    for _ in 0 ..< 30 { sim_tick(&host, 1.0 / 60.0) }
    testing.expect_value(t, _self_destruct_visible(&host.world), 0)
    testing.expect(t, world_tag_is_destroy(&host.world, hid), "host tags the entity after its timer")

    client := _test_sim()
    defer destroy_simulation(&client)
    client.role = .Client
    cid := world_create_entity(&client.world)
    comp_set(&client.world, cid, .SelfDestruct, SelfDestructComp{ timer = 0.25 })
    for _ in 0 ..< 30 { sim_tick(&client, 1.0 / 60.0) }
    testing.expect_value(t, _self_destruct_visible(&client.world), 1)
    testing.expect(t, !world_tag_is_destroy(&client.world, cid), "HostOnly system must not run on a client")
}
