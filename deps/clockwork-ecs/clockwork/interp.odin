package clockwork

import "core:math"

INTERP_DELAY :: f64(0.07)

Sample :: struct($T: typeid) {
	value: T,
	time:  f64,
}

Interpolator :: struct($T: typeid) {
	active:    bool,
	have_prev: bool,
	prev:      Sample(T),
	cur:       Sample(T),
	delay:     f64,
}

interp_reset :: proc(it: ^Interpolator($T)) {
	delay := it.delay
	it^ = {}
	it.delay = delay
}

interp_observe :: proc(it: ^Interpolator($T), value: T, now: f64) {
	if it.active {
		it.prev = it.cur
		it.have_prev = true
	}
	it.cur = Sample(T){value = value, time = now}
	it.active = true
}

interp_blend :: proc(it: ^Interpolator($T), now: f64) -> (a: T, b: T, t: f32, ok: bool) {
	if !it.active {return {}, {}, 0, false}
	if !it.have_prev {return it.cur.value, it.cur.value, 1, true}

	delay := it.delay > 0 ? it.delay : INTERP_DELAY
	span := it.cur.time - it.prev.time
	if span <= 0.0001 {return it.cur.value, it.cur.value, 1, true}

	render_time := now - delay
	f := f32((render_time - it.prev.time) / span)
	return it.prev.value, it.cur.value, clamp(f, 0, 1), true
}

interp_latest :: proc(it: ^Interpolator($T)) -> (value: T, ok: bool) {
	if !it.active {return {}, false}
	return it.cur.value, true
}

lerp_angle :: proc(a, b, t: f32) -> f32 {
	diff := b - a
	for diff > math.PI {diff -= 2 * math.PI}
	for diff < -math.PI {diff += 2 * math.PI}
	return a + diff * t
}
