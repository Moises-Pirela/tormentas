package server

// Headless server entry point (docs/BUILD_PLAN.md, P0 task 2).
//
// Today it proves one thing: the simulation core in src/sim links and runs with no graphics,
// audio, UI or Steam. It drives a Simulation exactly the way src/main.odin does (register
// systems, set role and state, tick at a fixed rate) and checks the results. P2 grows this
// into the world/instance server; until then, keep it to what src/sim can do on its own.
//
// usage: tormentas_server [--ticks N]     exit code 0 = sim behaved, 1 = invariant failed

import "core:fmt"
import "core:os"
import "core:strconv"
import sim "../sim"

TICK_RATE :: 60
TICK_DT   :: f32(1.0 / TICK_RATE)

main :: proc() {
    os.exit(0 if run() else 1)
}

run :: proc() -> bool {
    ticks := TICK_RATE * 10
    for a, i in os.args {
        if a == "--ticks" && i + 1 < len(os.args) {
            if v, ok := strconv.parse_int(os.args[i + 1]); ok && v > 0 { ticks = v }
        }
    }

    s := sim.make_simulation()
    defer sim.destroy_simulation(&s)
    s.role = .Host
    sim.sim_register_system(&s, {.Update}, sim.movement_system,      .Shared)
    sim.sim_register_system(&s, {.Update}, sim.self_destruct_system, .HostOnly)
    s.state = .Running

    w := &s.world
    mover := sim.world_create_entity(w)
    sim.comp_set(w, mover, .Transform, sim.TransformComp{})
    sim.comp_set(w, mover, .Velocity,  sim.VelocityComp{ value = { 30, -15, 0 } })

    fuse := sim.world_create_entity(w)
    sim.comp_set(w, fuse, .SelfDestruct, sim.SelfDestructComp{ timer = 0.5 })

    for _ in 0 ..< ticks { sim.sim_tick(&s, TICK_DT) }

    secs := f32(ticks) * TICK_DT
    pos  := sim.comp_get(w, mover, .Transform, sim.TransformComp).position
    ok   := true
    if s.world.tick != u64(ticks)                                 { ok = false; fmt.eprintln("[server] tick count drifted") }
    if abs(pos[0] - 30 * secs) > 0.1 || abs(pos[1] + 15 * secs) > 0.1 { ok = false; fmt.eprintln("[server] movement integration wrong") }
    if secs > 0.5 && sim.world_is_valid(w, fuse)                  { ok = false; fmt.eprintln("[server] self-destruct did not free its entity") }

    fmt.printfln("[server] headless sim: %d ticks (%.1fs) at %d Hz, mover at (%.1f, %.1f), %s",
        ticks, secs, TICK_RATE, pos[0], pos[1], "OK" if ok else "FAILED")
    return ok
}
