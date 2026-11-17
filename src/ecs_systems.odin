package main

projectile_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update {return}

    ids := world_query(w, query_mask(.Transform, .Projectile))
    defer delete(ids)

    for id in ids {
        t := comp_get(w, id, .Transform, TransformComp)
        p := comp_get(w, id, .Projectile, ProjectileComp)

        if !p.has_prev {
            p.prev_pos = projectile_segment_start(w, p, t.position)
            p.has_prev = true
        } else {
            p.prev_pos = { t.position[0], t.position[1] }
        }
        t.position[0] += p.direction[0] * p.speed * dt
        t.position[1] += p.direction[1] * p.speed * dt
        t.position[2] += p.direction[2] * p.speed * dt

        p.lifetime -= dt
        if p.lifetime <= 0 {
            world_tag_destroy(w, id)
        }
    }
}

make_default_simulation :: proc() -> Simulation {
    s := make_simulation()
    sim_register_system(&s, {.Update}, movement_system,      .Shared)
    sim_register_system(&s, {.Update}, projectile_system,    .HostOnly)
    sim_register_system(&s, {.Update}, self_destruct_system, .HostOnly)
    return s
}
