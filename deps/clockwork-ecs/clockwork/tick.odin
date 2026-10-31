package clockwork

DEFAULT_TICK_HZ             :: 30
MAX_FRAME_DT                :: f32(0.25)
MAX_STEPS_PER_FRAME         :: 5
MAX_CATCHUP_STEPS_PER_FRAME :: 1
INPUT_BACKLOG_TARGET        :: 1

Clock :: struct {
	hz:             int,
	dt:             f32,
	accumulator:    f32,
	max_steps:      int,
	max_catchup:    int,
	backlog_target: int,
}

clock_make :: proc(hz: int = DEFAULT_TICK_HZ) -> Clock {
	h := max(hz, 1)
	return Clock {
		hz             = h,
		dt             = f32(1.0) / f32(h),
		max_steps      = MAX_STEPS_PER_FRAME,
		max_catchup    = MAX_CATCHUP_STEPS_PER_FRAME,
		backlog_target = INPUT_BACKLOG_TARGET,
	}
}

clock_advance :: proc(c: ^Clock, frame_dt: f32) -> int {
	c.accumulator += min(frame_dt, MAX_FRAME_DT)

	steps := 0
	for c.accumulator >= c.dt && steps < c.max_steps {
		c.accumulator -= c.dt
		steps += 1
	}
	if steps == c.max_steps {c.accumulator = 0}
	return steps
}

clock_should_drain :: proc(c: ^Clock, backlog: int, taken: int, drained: int) -> bool {
	if backlog <= c.backlog_target {return false}
	if drained >= c.max_catchup {return false}
	return taken + drained < c.max_steps
}

clock_alpha :: proc(c: ^Clock) -> f32 {
	if c.dt <= 0 {return 0}
	return clamp(c.accumulator / c.dt, 0, 1)
}

clock_reset :: proc(c: ^Clock) {
	c.accumulator = 0
}
