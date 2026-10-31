package clockwork

import "core:slice"

// Systems register against lifecycle phases rather than being called by hand.
// A system names the phases it wants as a bit set, so one proc can serve
// several -- a spawner that wants `.Start` and `.EntityCreated`, say -- and the
// phase it is running in arrives as an argument.
//
//	sim_register(&sim, {.Update, .LateUpdate}, my_system, name = "game.doors")
//
// Dispatch order within a phase is `order` ascending, then registration order.
// Registering a name that already exists replaces it, which is how a project
// swaps out one of the engine's own systems.

Phase :: enum u16 {
	// Once, in order, around the life of the world.
	Init,
	Start,
	Stop,
	Shutdown,

	// Every tick, in this order.
	EarlyUpdate,
	PhysicsUpdate,
	Update,
	LateUpdate,

	// Drawing over the finished scene.
	Overlay,

	// Entity lifecycle. `.EntityDestroyed` runs while the entities are still
	// alive and readable -- `world_pending_destroy` lists them -- and
	// `.EntityCreated` runs after the sweep, with `world_created` listing the
	// ids that appeared this tick.
	EntityCreated,
	EntityDestroyed,

	// Free slots for a project that wants phases of its own.
	User0,
	User1,
	User2,
	User3,
	// Deferred events resolve after every producer has run.
	EndFrame,
}

PhaseMask :: distinct bit_set[Phase;u16]

// Whether a system may run on a client, or only where the world is
// authoritative. `.Shared` systems are the ones rollback replays.
Authority :: enum u8 {
	Shared,
	HostOnly,
}

SimRole :: enum u8 {
	Host,
	Client,
}

SimProc :: #type proc(w: ^World, phase: Phase, dt: f32)

SystemReg :: struct {
	name:      string,
	phases:    PhaseMask,
	fn:        SimProc,
	authority: Authority,

	// Lower runs first. Ties keep the order they were registered in.
	order: int,
	// Registered but skipped, for something a project toggles rather than drops.
	enabled: bool,
	// Whether the system still runs while the simulation is paused. Phases
	// outside the per-tick set ignore this.
	run_when_paused: bool,

	// Registration index, so sorting by order stays stable.
	seq: int,
}

Sim :: struct {
	systems: [dynamic]SystemReg,
	role:    SimRole,
	paused:  bool,
	sorted:  bool,
}

sim_destroy :: proc(s: ^Sim) {
	delete(s.systems)
	s^ = {}
}

sim_register :: proc(
	s: ^Sim,
	phases: PhaseMask,
	fn: SimProc,
	name := "",
	authority: Authority = .HostOnly,
	order := 0,
	run_when_paused := false,
) {
	if fn == nil {
		return
	}

	if name != "" {
		for &reg in s.systems {
			if reg.name != name {
				continue
			}
			reg.phases = phases
			reg.fn = fn
			reg.authority = authority
			reg.order = order
			reg.run_when_paused = run_when_paused
			reg.enabled = true
			s.sorted = false
			return
		}
	}

	append(&s.systems, SystemReg {
		name            = name,
		phases          = phases,
		fn              = fn,
		authority       = authority,
		order           = order,
		enabled         = true,
		run_when_paused = run_when_paused,
		seq             = len(s.systems),
	})
	s.sorted = false
}

sim_remove :: proc(s: ^Sim, name: string) -> bool {
	for reg, i in s.systems {
		if reg.name != name {
			continue
		}
		ordered_remove(&s.systems, i)
		s.sorted = false
		return true
	}
	return false
}

sim_set_enabled :: proc(s: ^Sim, name: string, enabled: bool) -> bool {
	for &reg in s.systems {
		if reg.name != name {
			continue
		}
		reg.enabled = enabled
		return true
	}
	return false
}

sim_find :: proc(s: ^Sim, name: string) -> (^SystemReg, bool) {
	for &reg in s.systems {
		if reg.name == name {
			return &reg, true
		}
	}
	return nil, false
}

// Every registered system in dispatch order, for a project that wants to show
// the schedule or assert against it.
sim_systems :: proc(s: ^Sim) -> []SystemReg {
	sim_sort(s)
	return s.systems[:]
}

@(private)
sim_sort :: proc(s: ^Sim) {
	if s.sorted {
		return
	}
	slice.sort_by(s.systems[:], proc(a, b: SystemReg) -> bool {
		if a.order != b.order {
			return a.order < b.order
		}
		return a.seq < b.seq
	})
	s.sorted = true
}

@(private)
_pausable :: proc(phase: Phase) -> bool {
	switch phase {
	case .EarlyUpdate, .PhysicsUpdate, .Update, .LateUpdate, .EndFrame:
		return true
	case .Init, .Start, .Stop, .Shutdown, .Overlay,
	     .EntityCreated, .EntityDestroyed,
	     .User0, .User1, .User2, .User3:
		return false
	}
	return false
}

sim_dispatch :: proc(s: ^Sim, w: ^World, phase: Phase, dt: f32) {
	sim_sort(s)
	skip_paused := s.paused && _pausable(phase)

	for reg in s.systems {
		if phase not_in reg.phases || !reg.enabled {
			continue
		}
		if s.role == .Client && reg.authority == .HostOnly {
			continue
		}
		if skip_paused && !reg.run_when_paused {
			continue
		}
		reg.fn(w, phase, dt)
	}
}

// Replays the systems a rollback is allowed to re-run: shared authority, on
// `.Update` only, ignoring the pause gate because a replay is catching up.
sim_replay :: proc(s: ^Sim, w: ^World, dt: f32) {
	sim_sort(s)
	for reg in s.systems {
		if Phase.Update not_in reg.phases || !reg.enabled {
			continue
		}
		if reg.authority != .Shared {
			continue
		}
		reg.fn(w, .Update, dt)
	}
}

// One simulation tick. Physics is not stepped here -- a host that owns a
// physics world steps it inside its `.PhysicsUpdate` systems, or around this
// call, so a headless tick stays free of that dependency.
sim_tick :: proc(s: ^Sim, w: ^World, dt: f32) {
	sim_dispatch(s, w, .EarlyUpdate, dt)
	sim_dispatch(s, w, .PhysicsUpdate, dt)
	sim_dispatch(s, w, .Update, dt)
	sim_dispatch(s, w, .LateUpdate, dt)
	sim_dispatch(s, w, .EndFrame, dt)
	sim_entity_lifecycle(s, w, dt)
	w.tick += 1
}

// Dispatches the destroy phase while the entities can still be read, sweeps
// them, then announces whatever was created during the tick.
sim_entity_lifecycle :: proc(s: ^Sim, w: ^World, dt: f32) {
	if len(w.pending_destroy) > 0 {
		sim_dispatch(s, w, .EntityDestroyed, dt)
	}
	world_sweep(w)
	if len(w.created) > 0 {
		sim_dispatch(s, w, .EntityCreated, dt)
		clear(&w.created)
	}
}
