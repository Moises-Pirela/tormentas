package main

import "core:math"
import rl "vendor:raylib"

grenade_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    {
        grenade_ids := world_query(w, query_mask(.Grenade, .Transform))
        defer delete(grenade_ids)

        for gid in grenade_ids {
            g := comp_get(w, gid, .Grenade, GrenadeComp)
            t := comp_get(w, gid, .Transform, TransformComp)

            dx   := g.target[0] - t.position[0]
            dy   := g.target[1] - t.position[1]
            dist := math.sqrt(dx*dx + dy*dy)

            g.fuse_timer -= dt

            arrived := dist <= g.speed * dt || g.fuse_timer <= 0

            if !arrived {
                step          := g.speed * dt
                inv           := step / dist
                t.position[0] += dx * inv
                t.position[1] += dy * inv
            } else {
                t.position = g.target
                _grenade_detonate(w, gid)
                world_destroy_entity(w, gid)
            }
        }
    }

    {
        cloud_ids := world_query(w, query_mask(.PoisonCloud, .Transform))
        defer delete(cloud_ids)

        for cid in cloud_ids {
            cl := comp_get(w, cid, .PoisonCloud, PoisonCloudComp)
            t  := comp_get(w, cid, .Transform, TransformComp)

            cl.duration   -= dt
            cl.tick_timer -= dt

            if cl.tick_timer <= 0 {
                cl.tick_timer = cl.tick_interval
                tick_dmg := cl.dps * cl.tick_interval
                _cloud_damage_nearby(w, cl.owner_id, t.position, cl.radius,
                    tick_dmg, cl.cloud_status, cl.cloud_status_dur)
            }

            if cl.duration <= 0 {
                world_destroy_entity(w, cid)
            }
        }
    }
}

@(private = "file")
_grenade_detonate :: proc(w: ^World, gid: int) {
    g   := comp_get(w, gid, .Grenade, GrenadeComp)
    pos := comp_get(w, gid, .Transform, TransformComp).position

    if g.blink_on_land && world_is_valid(w, g.owner_id) &&
       world_has_component(w, g.owner_id, .Transform) {
        ot := comp_get(w, g.owner_id, .Transform, TransformComp)
        ot.position = pos

        if world_has_component(w, g.owner_id, .Velocity) {
            comp_get(w, g.owner_id, .Velocity, VelocityComp).value = {}
        }
    }

    _cloud_damage_nearby(w, g.owner_id, pos, g.blast_radius, g.damage, g.cloud_status, 0)

    push_explosion(pos[0], pos[1], g.blast_radius, g.er, g.eg, g.eb)
    play_sfx("ability_fan")

    if g.cloud_duration > 0 {
        cloud_id := world_create_entity(w)
        comp_set(w, cloud_id, .Transform, TransformComp{ position = pos })
        comp_set(w, cloud_id, .PoisonCloud, PoisonCloudComp{
            owner_id         = g.owner_id,
            radius           = g.cloud_radius,
            dps              = g.cloud_dps,
            duration         = g.cloud_duration,
            tick_timer       = 0,
            tick_interval    = 0.5,
            cloud_status     = g.cloud_status,
            cloud_status_dur = g.cloud_status_dur,
            er               = g.er,
            eg               = g.eg,
            eb               = g.eb,
        })
    }
}

@(private = "file")
_cloud_damage_nearby :: proc(w: ^World, owner_id: int,
                              pos: [3]f32, radius, amount: f32,
                              status: StatusEffectType = .Poison,
                              status_dur: f32 = 0) {
    r2  := radius * radius
    ids := world_query(w, query_mask(.AIAgent, .Health, .Transform))
    defer delete(ids)
    for eid in ids {
        et := comp_get(w, eid, .Transform, TransformComp)
        dx := et.position[0] - pos[0]
        dy := et.position[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        if amount > 0 {
            world_push_damage(w, eid, amount, owner_id)
        }
        if status_dur > 0 {
            status_effect_apply(w, eid, StatusEffect{
                type           = status,
                application    = .Base,
                stack_behavior = .Refresh,
                duration       = status_dur,
                strength       = 1.0,
            })
        }
    }
}

draw_grenades_and_clouds :: proc(w: ^World) {
    {
        cloud_ids := world_query(w, query_mask(.PoisonCloud, .Transform))
        defer delete(cloud_ids)

        for cid in cloud_ids {
            cl  := comp_get(w, cid, .PoisonCloud, PoisonCloudComp)
            pos := rl.Vector2{
                comp_get(w, cid, .Transform, TransformComp).position[0],
                comp_get(w, cid, .Transform, TransformComp).position[1],
            }

            life_frac := clamp(cl.duration / cl.tick_interval / 16.0, 0, 1)
            pulse     := f32(0.65) + f32(0.35) * math.sin_f32(cl.duration * 4.0)
            fill_a    := u8(clamp(life_frac * pulse * 55,  0, 255))
            edge_a    := u8(clamp(life_frac * pulse * 160, 0, 255))

            draw_world_circle(pos, cl.radius,        rl.Color{ cl.er, cl.eg, cl.eb, fill_a })

            draw_world_circle_lines(pos, cl.radius,  rl.Color{ cl.er, cl.eg, cl.eb, edge_a })

            draw_world_circle_lines(pos, cl.radius * 0.52,
                rl.Color{ 220, 255, 180, u8(clamp(f32(edge_a) * 0.45, 0, 255)) })
        }
    }

    {
        grenade_ids := world_query(w, query_mask(.Grenade, .Transform))
        defer delete(grenade_ids)

        for gid in grenade_ids {
            g   := comp_get(w, gid, .Grenade, GrenadeComp)
            pos := rl.Vector2{
                comp_get(w, gid, .Transform, TransformComp).position[0],
                comp_get(w, gid, .Transform, TransformComp).position[1],
            }

            draw_world_circle(pos, 7,  rl.Color{ g.er, g.eg, g.eb, 230 })
            draw_world_circle(pos, 3,  rl.Color{ 230, 255, 200, 255 })
        }
    }
}
