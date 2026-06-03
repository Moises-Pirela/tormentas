package main


import "core:math"
import cw "clockwork"
import rl "vendor:raylib"


trap_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    trap_ids := cw.world_query(w, cw.query_mask(.ProximityTrigger, .Transform))
    defer delete(trap_ids)

    for tid in trap_ids {
        trap := cw.world_get_proximity_trigger(w, tid)
        pos  := cw.world_get_transform(w, tid).position


        if trap.arm_timer > 0 {
            trap.arm_timer -= dt
            continue
        }


        r2     := trap.radius * trap.radius
        ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
        triggered := false
        for eid in ai_ids {
            et := cw.world_get_transform(w, eid)
            dx := et.position[0] - pos[0]
            dy := et.position[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }


            cw.world_push_damage(w, eid, trap.damage, trap.owner_id)
            if trap.status_dur > 0 {
                cw.status_effect_apply(w, eid, cw.StatusEffect{
                    type           = trap.status,
                    application    = .Base,
                    stack_behavior = .Refresh,
                    duration       = trap.status_dur,
                    strength       = trap.status_str,
                })
            }
            triggered = true
            break
        }

        if triggered {
            push_explosion(pos[0], pos[1], trap.radius, trap.er, trap.eg, trap.eb)
            play_sfx("ability_fan")
            cw.world_destroy_entity(w, tid)
        }
    }
}


draw_traps :: proc(w: ^cw.World) {
    trap_ids := cw.world_query(w, cw.query_mask(.ProximityTrigger, .Transform))
    defer delete(trap_ids)

    for tid in trap_ids {
        trap := cw.world_get_proximity_trigger(w, tid)
        pos  := rl.Vector2{
            cw.world_get_transform(w, tid).position[0],
            cw.world_get_transform(w, tid).position[1],
        }

        armed := trap.arm_timer <= 0


        pulse    := f32(1.0)
        fill_a   := u8(40)
        edge_a   := u8(120)
        if armed {
            pulse  = 0.7 + 0.3 * math.sin_f32(f32(cw.world_get_transform(w, tid).rotation))


            fill_a = u8(clamp(f32(fill_a) * pulse, 0, 255))
            edge_a = u8(clamp(f32(edge_a) * pulse, 0, 255))
        }


        draw_world_circle_lines(pos, trap.radius,
            rl.Color{ trap.er, trap.eg, trap.eb, edge_a })


        core_color := rl.Color{ trap.er, trap.eg, trap.eb, u8(armed ? 200 : 80) }
        draw_world_circle(pos, 6, core_color)


        draw_world_circle(pos, trap.radius, rl.Color{ trap.er, trap.eg, trap.eb, fill_a })
    }
}
