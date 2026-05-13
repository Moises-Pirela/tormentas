package main

import rl  "vendor:raylib"
import     "core:math"
import cw  "clockwork"
import p2p "p2p"

g_staged_input: [cw.MAX_PLAYERS]p2p.InputFrame

collect_local_input :: proc() -> p2p.InputFrame {
    f: p2p.InputFrame
    f.peer = 0

    if g_console_open { return f }

    screen_dir: [2]f32
    if rl.IsKeyDown(rl.KeyboardKey(g_binds.gameplay.move_up))    || rl.IsKeyDown(.UP)    { screen_dir[1] -= 1 }
    if rl.IsKeyDown(rl.KeyboardKey(g_binds.gameplay.move_down))  || rl.IsKeyDown(.DOWN)  { screen_dir[1] += 1 }
    if rl.IsKeyDown(rl.KeyboardKey(g_binds.gameplay.move_left))  || rl.IsKeyDown(.LEFT)  { screen_dir[0] -= 1 }
    if rl.IsKeyDown(rl.KeyboardKey(g_binds.gameplay.move_right)) || rl.IsKeyDown(.RIGHT) { screen_dir[0] += 1 }
    mag := math.sqrt(screen_dir[0]*screen_dir[0] + screen_dir[1]*screen_dir[1])
    if mag > 0 {
        screen_dir[0] /= mag
        screen_dir[1] /= mag
    }
    f.move = screen_dir_to_world_dir(screen_dir)

    mp    := screen_to_world_cartesian(rl.GetMousePosition())
    f.aim  = { mp.x, mp.y }

    if rl.IsMouseButtonDown(.LEFT)                                { f.actions += {.Fire}     }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.reload))  { f.actions += {.Reload}   }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.dodge))   { f.actions += {.Dodge}    }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.skill1))  { f.actions += {.Skill1}   }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.skill2))  { f.actions += {.Skill2}   }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.skill3))  { f.actions += {.Skill3}   }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.skill4))  { f.actions += {.Skill4}   }
    if rl.IsKeyPressed(rl.KeyboardKey(g_binds.gameplay.interact)){ f.actions += {.Interact} }
    return f
}

apply_input_frame :: proc(w: ^cw.World, entity_id: int, f: p2p.InputFrame) {
    cw.world_set_input(w, entity_id, cw.InputStateComp{
        move             = f.move,
        mouse_world      = { f.aim[0], f.aim[1], 0 },
        fire_pressed     = .Fire     in f.actions,
        reload_pressed   = .Reload   in f.actions,
        dodge_pressed    = .Dodge    in f.actions,
        skill1_pressed   = .Skill1   in f.actions,
        skill2_pressed   = .Skill2   in f.actions,
        skill3_pressed   = .Skill3   in f.actions,
        skill4_pressed   = .Skill4   in f.actions,
        interact_pressed = .Interact in f.actions,
    })
}

player_input_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .EarlyUpdate { return }

    for slot in 0..<cw.MAX_PLAYERS {
        id := w.player_ids[slot]
        if !cw.world_is_valid(w, id) { continue }

        if cw.world_has_component(w, id, .Respawn) &&
           cw.world_get_respawn(w, id).timer > 0 {
            cw.world_set_input(w, id, cw.InputStateComp{})
            cw.world_set_velocity(w, id, cw.VelocityComp{})
            continue
        }

        frame := g_staged_input[slot]
        apply_input_frame(w, id, frame)

        move := frame.move
        move_speed := f32(MOVE_SPEED)
        if cw.world_has_component(w, id, .Stats) {
            st := cw.world_get_stats(w, id)
            move_speed = st.move_speed
            if st.movement_blocked { move = {} }
        }
        cw.world_set_velocity(w, id, cw.VelocityComp{
            value = { move[0] * move_speed, move[1] * move_speed, 0 },
        })
    }
}

dodge_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .EarlyUpdate { return }

    for slot in 0..<cw.MAX_PLAYERS {
        id := w.player_ids[slot]
        if !cw.world_is_valid(w, id) { continue }
        if !cw.world_has_component(w, id, .DodgeState) { continue }

        input := cw.world_get_input(w, id)
        dodge := cw.world_get_dodge(w, id)
        t     := cw.world_get_transform(w, id)

        if dodge.active {
            dodge.timer -= dt
            if dodge.timer <= 0 {
                dodge.active   = false
                dodge.timer    = 0
                dodge.cooldown = dodge.cooldown_max
                reduction      := f32(0)
                if cw.world_has_component(w, id, .Stats) {
                    reduction = cw.world_get_stats(w, id).dodge_cooldown_reduction
                }
                dodge.cooldown  = max(0, dodge.cooldown - reduction)
            }
        } else if dodge.cooldown > 0 {
            dodge.cooldown -= dt
            if dodge.cooldown < 0 { dodge.cooldown = 0 }
        }

        can_dodge_charge := false
        if input.dodge_pressed && !dodge.active && dodge.cooldown > 0 {
            if cw.world_has_component(w, id, .MutationContainer) {
                mc := cw.world_get_mutation(w, id)
                for mi in 0..<mc.entity_count {
                    meid := mc.entities[mi]
                    if !cw.world_is_valid(w, meid)                           { continue }
                    if !cw.world_has_component(w, meid, .MutExtraDodgeCharges) { continue }
                    edc := cw.world_get_mut_extra_dodge_charges(w, meid)
                    if edc.charges > 0 {
                        edc.charges       -= 1
                        edc.recharge_timer = 0
                        can_dodge_charge   = true
                    }
                    break
                }
            }
        }

        if input.dodge_pressed && !dodge.active && (dodge.cooldown <= 0 || can_dodge_charge) {
            dodge.active    = true
            dodge.timer     = dodge.duration
            dodge.direction = {
                math.cos(t.rotation),
                math.sin(t.rotation),
            }
            if id == w.player_id { play_sfx("dodge") }
        }

        if dodge.active {
            cw.world_set_velocity(w, id, cw.VelocityComp{
                value = {
                    dodge.direction[0] * dodge.speed,
                    dodge.direction[1] * dodge.speed,
                    0,
                },
            })
        }
    }
}

facing_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    for slot in 0..<cw.MAX_PLAYERS {
        id := w.player_ids[slot]
        if !cw.world_is_valid(w, id) { continue }
        if !cw.world_has_component(w, id, .Transform) { continue }
        if !cw.world_has_component(w, id, .InputState) { continue }

        t     := cw.world_get_transform(w, id)
        input := cw.world_get_input(w, id)

        dx := input.mouse_world[0] - t.position[0]
        dy := input.mouse_world[1] - t.position[1]
        if abs(dx) > 0.01 || abs(dy) > 0.01 {
            t.rotation = math.atan2(dy, dx)
        }
    }
}

camera_follow_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }
    if g_editor_mode { return }  // editor pans camera itself via WASD
    if !cw.world_is_valid(w, w.player_id) { return }

    pos := cw.world_get_transform(w, w.player_id).position
    camera_set_target_world(pos[0], pos[1])
}
