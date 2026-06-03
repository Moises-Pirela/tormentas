package main


import "core:math"
import cw "clockwork"
import rl "vendor:raylib"


grenade_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }


    {
        grenade_ids := cw.world_query(w, cw.query_mask(.Grenade, .Transform))
        defer delete(grenade_ids)

        for gid in grenade_ids {
            g := cw.world_get_grenade(w, gid)
            t := cw.world_get_transform(w, gid)

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
                cw.world_destroy_entity(w, gid)
            }
        }
    }


    {
        cloud_ids := cw.world_query(w, cw.query_mask(.PoisonCloud, .Transform))
        defer delete(cloud_ids)

        for cid in cloud_ids {
            cl := cw.world_get_poison_cloud(w, cid)
            t  := cw.world_get_transform(w, cid)

            cl.duration   -= dt
            cl.tick_timer -= dt

            if cl.tick_timer <= 0 {
                cl.tick_timer = cl.tick_interval
                tick_dmg := cl.dps * cl.tick_interval
                _cloud_damage_nearby(w, cl.owner_id, t.position, cl.radius,
                    tick_dmg, cl.cloud_status, cl.cloud_status_dur)
            }

            if cl.duration <= 0 {
                cw.world_destroy_entity(w, cid)
            }
        }
    }
}


@(private = "file")
_grenade_detonate :: proc(w: ^cw.World, gid: int) {
    g   := cw.world_get_grenade(w, gid)
    pos := cw.world_get_transform(w, gid).position


    if g.blink_on_land && cw.world_is_valid(w, g.owner_id) &&
       cw.world_has_component(w, g.owner_id, .Transform) {
        ot := cw.world_get_transform(w, g.owner_id)
        ot.position = pos

        if cw.world_has_component(w, g.owner_id, .Velocity) {
            cw.world_get_velocity(w, g.owner_id).value = {}
        }
    }


    _cloud_damage_nearby(w, g.owner_id, pos, g.blast_radius, g.damage, g.cloud_status, 0)


    push_explosion(pos[0], pos[1], g.blast_radius, g.er, g.eg, g.eb)
    play_sfx("ability_fan")


    if g.cloud_duration > 0 {
        cloud_id := cw.world_create_entity(w)
        cw.world_set_transform(w, cloud_id, cw.TransformComp{ position = pos })
        cw.world_set_poison_cloud(w, cloud_id, cw.PoisonCloudComp{
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
_cloud_damage_nearby :: proc(w: ^cw.World, owner_id: int,
                              pos: [3]f32, radius, amount: f32,
                              status: cw.StatusEffectType = .Poison,
                              status_dur: f32 = 0) {
    r2  := radius * radius
    ids := cw.world_query(w, cw.query_mask(.AIAgent, .Health, .Transform))
    defer delete(ids)
    for eid in ids {
        et := cw.world_get_transform(w, eid)
        dx := et.position[0] - pos[0]
        dy := et.position[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        if amount > 0 {
            cw.world_push_damage(w, eid, amount, owner_id)
        }
        if status_dur > 0 {
            cw.status_effect_apply(w, eid, cw.StatusEffect{
                type           = status,
                application    = .Base,
                stack_behavior = .Refresh,
                duration       = status_dur,
                strength       = 1.0,
            })
        }
    }
}


draw_grenades_and_clouds :: proc(w: ^cw.World) {

    {
        cloud_ids := cw.world_query(w, cw.query_mask(.PoisonCloud, .Transform))
        defer delete(cloud_ids)

        for cid in cloud_ids {
            cl  := cw.world_get_poison_cloud(w, cid)
            pos := rl.Vector2{
                cw.world_get_transform(w, cid).position[0],
                cw.world_get_transform(w, cid).position[1],
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
        grenade_ids := cw.world_query(w, cw.query_mask(.Grenade, .Transform))
        defer delete(grenade_ids)

        for gid in grenade_ids {
            g   := cw.world_get_grenade(w, gid)
            pos := rl.Vector2{
                cw.world_get_transform(w, gid).position[0],
                cw.world_get_transform(w, gid).position[1],
            }

            draw_world_circle(pos, 7,  rl.Color{ g.er, g.eg, g.eb, 230 })
            draw_world_circle(pos, 3,  rl.Color{ 230, 255, 200, 255 })
        }
    }
}
