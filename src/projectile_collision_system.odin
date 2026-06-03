package main

import "core:math"
import cw "clockwork"

PROJ_RADIUS :: f32(4)

projectile_collision_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    proj_ids   := cw.world_query(w, cw.query_mask(.ProjectileTag, .Projectile, .Transform))
    defer delete(proj_ids)

    target_ids := cw.world_query(w, cw.query_mask(.Collider, .Health, .Transform))
    defer delete(target_ids)

    for proj_id in proj_ids {
        if cw.world_tag_is_destroy(w, proj_id) { continue }

        proj   := cw.world_get_projectile(w, proj_id)
        proj_t := cw.world_get_transform(w, proj_id)

        for target_id in target_ids {
            if target_id == proj_id { continue }

            col := cw.world_get_collider(w, target_id)
            if col.faction == proj.owner_faction { continue }

            target_t := cw.world_get_transform(w, target_id)
            dx := target_t.position[0] - proj_t.position[0]
            dy := target_t.position[1] - proj_t.position[1]
            dist := math.sqrt(dx*dx + dy*dy)

            if dist < PROJ_RADIUS + col.radius {
                cw.world_push_damage(w, target_id, proj.damage, proj.owner_id)


                if cw.world_has_component(w, proj_id, .DamageAmpOnHit) {
                    dah := cw.world_get_damage_amp_on_hit(w, proj_id)
                    if cw.world_has_component(w, target_id, .DamageAmp) {
                        da       := cw.world_get_damage_amp(w, target_id)
                        da.mult  *= dah.mult
                        da.timer  = max(da.timer, dah.dur)
                    } else {
                        cw.world_set_damage_amp(w, target_id, cw.DamageAmpComp{
                            mult  = dah.mult,
                            timer = dah.dur,
                        })
                    }
                    cw.world_clear_damage_amp_on_hit(w, proj_id)
                }

                if target_id != w.player_id {
                    play_sfx_at("impact", target_t.position)
                }
                if proj.pierce_remaining > 0 {
                    proj.pierce_remaining -= 1
                } else {
                    cw.world_tag_destroy(w, proj_id)
                    break
                }
            }
        }
    }
}
