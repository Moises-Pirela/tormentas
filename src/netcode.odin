package main

import ecs "cw:clockwork"
import p2p "p2p"
import "core:math"
import rl  "vendor:raylib"

PredictReconcileState :: struct {
    pos: [3]f32,
    vel: [3]f32,
    rot: f32,
}

g_predictor:       ecs.Predictor(p2p.InputFrame, PredictReconcileState)
g_predictor_ready: bool
g_shadow_map:      map[u32]int
g_last_peer_input: [MAX_PLAYERS]p2p.InputFrame

ShadowPose :: struct {
    pos: [3]f32,
    rot: f32,
}
g_shadow_interp: map[u32]ecs.Interpolator(ShadowPose)

netcode_predict_apply :: proc(w: ^ecs.World, id: ecs.EntityId, input: p2p.InputFrame, dt: f32) {
    if !g_sim_alive { return }
    g_staged_input[g_sim.world.local_player_slot] = input
    sim_tick_predicted(&g_sim, dt)
}

netcode_predict_restore :: proc(w: ^ecs.World, id: ecs.EntityId, state: PredictReconcileState) {
    if !g_sim_alive { return }
    eid := int(id)
    if !world_is_valid(&g_sim.world, eid) { return }
    if world_has_component(&g_sim.world, eid, .Transform) {
        t := comp_get(&g_sim.world, eid, .Transform, TransformComp)
        t.position = state.pos
        t.rotation = state.rot
    }
    if world_has_component(&g_sim.world, eid, .Velocity) {
        comp_get(&g_sim.world, eid, .Velocity, VelocityComp).value = state.vel
    }
}

netcode_predict_read_pos :: proc(w: ^ecs.World, id: ecs.EntityId) -> [3]f32 {
    if !g_sim_alive { return {} }
    eid := int(id)
    if !world_is_valid(&g_sim.world, eid) { return {} }
    if !world_has_component(&g_sim.world, eid, .Transform) { return {} }
    return comp_get(&g_sim.world, eid, .Transform, TransformComp).position
}

netcode_predictor_init :: proc() {
    if !g_sim_alive { return }
    ecs.predict_init(&g_predictor, ecs.EntityId(g_sim.world.player_id),
        netcode_predict_apply, netcode_predict_restore, netcode_predict_read_pos)
    g_predictor_ready = true
    g_last_peer_input = {}
    clear(&g_shadow_map)
    clear(&g_shadow_interp)
}

netcode_predictor_shutdown :: proc() {
    g_predictor        = {}
    g_predictor_ready  = false
    for _, id in g_shadow_map {
        if g_sim_alive && world_is_valid(&g_sim.world, id) {
            world_destroy_entity(&g_sim.world, id)
        }
    }
    clear(&g_shadow_map)
    clear(&g_shadow_interp)
}

netcode_host_tick :: proc(host_input: p2p.InputFrame, dt: f32) {
    w := &g_sim.world

    g_staged_input[0] = host_input
    for &p in g_session.peers {
        if !p.active || !p.connected { continue }
        if p.has_client_input {
            g_last_peer_input[p.slot] = p.latest_client_input
            p.has_client_input        = false
        }
        g_staged_input[p.slot] = g_last_peer_input[p.slot]
    }

    sim_tick(&g_sim, dt)

    if !p2p.session_is_online(&g_session) { return }

    entities := make([dynamic]p2p.SyncEntity, 0, 128, context.temp_allocator)

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) || !world_has_component(w, pid, .Transform) { continue }
        append(&entities, _netcode_snapshot_entity(w, pid, .Player, u8(slot)))
    }

    ai_ids := world_query(w, query_mask(.AIAgent, .Transform))
    for id in ai_ids {
        if len(entities) >= p2p.MAX_SNAPSHOT_ENTITIES { break }
        append(&entities, _netcode_snapshot_entity(w, id, .Enemy, 0))
    }
    delete(ai_ids)

    proj_ids := world_query(w, query_mask(.ProjectileTag, .Transform))
    for id in proj_ids {
        if len(entities) >= p2p.MAX_SNAPSHOT_ENTITIES { break }
        append(&entities, _netcode_snapshot_entity(w, id, .Projectile, 0))
    }
    delete(proj_ids)

    ack_by_slot: [MAX_PLAYERS]u32
    for &p in g_session.peers {
        if !p.active || !p.connected { continue }
        ack_by_slot[p.slot] = g_last_peer_input[p.slot].tick
    }

    p2p.session_broadcast_snapshot(&g_session, ack_by_slot, entities[:])
}

@(private = "file")
_magnitude2 :: proc(v: [3]f32) -> f32 {
    return math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
}

@(private = "file")
_netcode_snapshot_entity :: proc(w: ^World, id: int, kind: p2p.SyncKind, slot: u8) -> p2p.SyncEntity {
    t := comp_get(w, id, .Transform, TransformComp)
    vel: [3]f32
    if world_has_component(w, id, .Velocity) {
        vel = comp_get(w, id, .Velocity, VelocityComp).value
    } else if world_has_component(w, id, .Projectile) {
        p := comp_get(w, id, .Projectile, ProjectileComp)
        vel = { p.direction[0]*p.speed, p.direction[1]*p.speed, p.direction[2]*p.speed }
    }
    hp_frac := u8(255)
    if world_has_component(w, id, .Health) {
        h := comp_get(w, id, .Health, HealthComp)
        if h.max > 0 { hp_frac = u8(clamp(h.current / h.max, 0, 1) * 255) }
    }
    archetype := u8(0)
    if kind == .Enemy && world_has_component(w, id, .AIAgent) {
        archetype = comp_get(w, id, .AIAgent, AIAgentComp).roster_index
    }
    return p2p.SyncEntity{
        wire_id = u32(id), kind = kind, slot = slot,
        pos = t.position, rot = t.rotation, vel = vel, hp_frac = hp_frac,
        archetype = archetype,
    }
}

netcode_client_tick :: proc(input: p2p.InputFrame, dt: f32) {
    if !g_predictor_ready { return }

    seq := ecs.predict_step(&g_predictor, &g_sim.world.base, input, dt)
    stamped := input
    stamped.tick = seq
    p2p.session_send_client_input(&g_session, stamped)

    if g_session.has_snapshot {
        reconcile: PredictReconcileState
        for e in g_session.snapshot_entities {
            if e.kind == .Player && int(e.slot) == g_sim.world.local_player_slot {
                reconcile.pos = e.pos
                reconcile.rot = e.rot
                reconcile.vel = e.vel
                break
            }
        }
        ecs.predict_reconcile(&g_predictor, &g_sim.world.base,
            reconcile, g_session.snapshot_ack, dt)
        _netcode_apply_snapshot(g_session.snapshot_entities[:])
        g_session.has_snapshot = false
    }

    ecs.predict_decay_error(&g_predictor, dt)
}

_netcode_apply_snapshot :: proc(entities: []p2p.SyncEntity) {
    w   := &g_sim.world
    now := f64(rl.GetTime())
    seen: map[u32]bool
    defer delete(seen)

    for e in entities {
        if e.kind == .Player {
            pid := w.player_ids[e.slot]
            if !world_is_valid(w, pid) { continue }
            if int(e.slot) == w.local_player_slot { continue }
            if world_has_component(w, pid, .Transform) {
                t := comp_get(w, pid, .Transform, TransformComp)
                t.position = e.pos
                t.rotation = e.rot
            }
            if world_has_component(w, pid, .Velocity) {
                comp_get(w, pid, .Velocity, VelocityComp).value = e.vel
            }
            if world_has_component(w, pid, .Health) {
                h := comp_get(w, pid, .Health, HealthComp)
                if h.max > 0 { h.current = f32(e.hp_frac) / 255.0 * h.max }
            }
            continue
        }

        seen[e.wire_id] = true
        id, exists := g_shadow_map[e.wire_id]
        if !exists || !world_is_valid(w, id) {
            if e.kind == .Enemy {
                roster_name := DIRECTOR_ROSTER[0].name
                if int(e.archetype) < len(DIRECTOR_ROSTER) {
                    roster_name = DIRECTOR_ROSTER[e.archetype].name
                }
                def := find_entity_def(g_entity_defs, roster_name)
                if def == nil { continue }
                id = spawn_from_def(w, def)
                if id == INVALID_ENTITY { continue }
            } else {
                id = world_create_entity(w)
                comp_set(w, id, .Transform, TransformComp{})
                comp_set(w, id, .Projectile, ProjectileComp{ visual = .Standard })
                comp_add(w, id, .ProjectileTag)
            }
            g_shadow_map[e.wire_id] = id
        }
        if world_has_component(w, id, .Transform) {
            it := g_shadow_interp[e.wire_id]
            ecs.interp_observe(&it, ShadowPose{ pos = e.pos, rot = e.rot }, now)
            g_shadow_interp[e.wire_id] = it
        }
        if world_has_component(w, id, .Velocity) {
            comp_get(w, id, .Velocity, VelocityComp).value = e.vel
        }
        if e.kind == .Projectile && world_has_component(w, id, .Projectile) {
            p   := comp_get(w, id, .Projectile, ProjectileComp)
            spd := _magnitude2(e.vel)
            p.speed = spd
            if spd > 0.001 {
                p.direction = { e.vel[0]/spd, e.vel[1]/spd, e.vel[2]/spd }
            }
        }
        if world_has_component(w, id, .Health) {
            h := comp_get(w, id, .Health, HealthComp)
            if h.max > 0 { h.current = f32(e.hp_frac) / 255.0 * h.max }
        }
    }

    for wire_id, id in g_shadow_map {
        if seen[wire_id] { continue }
        if world_is_valid(w, id) { world_destroy_entity(w, id) }
        delete_key(&g_shadow_map, wire_id)
        delete_key(&g_shadow_interp, wire_id)
    }
}

netcode_interp_update :: proc() {
    if !g_sim_alive || g_sim.role != .Client { return }
    w   := &g_sim.world
    now := f64(rl.GetTime())

    for wire_id, id in g_shadow_map {
        if !world_is_valid(w, id) || !world_has_component(w, id, .Transform) { continue }
        it := g_shadow_interp[wire_id]
        a, b, t, ok := ecs.interp_blend(&it, now)
        if !ok { continue }
        tr := comp_get(w, id, .Transform, TransformComp)
        tr.position = {
            a.pos[0] + (b.pos[0] - a.pos[0]) * t,
            a.pos[1] + (b.pos[1] - a.pos[1]) * t,
            a.pos[2] + (b.pos[2] - a.pos[2]) * t,
        }
        tr.rotation = ecs.lerp_angle(a.rot, b.rot, t)
    }
}
