package clockwork

import "core:math"

MAX_PENDING      :: 256
ERROR_DECAY_RATE :: f32(14.0)

Predictor :: struct($I: typeid, $S: typeid) {
	entity:      EntityId,
	ready:       bool,
	primed:      bool,

	pending:     [MAX_PENDING]PendingInput(I),
	pending_n:   int,
	next_seq:    u32,

	apply:       proc(w: ^World, id: EntityId, input: I, dt: f32),
	restore:     proc(w: ^World, id: EntityId, state: S),
	read_pos:    proc(w: ^World, id: EntityId) -> [3]f32,

	error:       [3]f32,
	prev_pos:    [3]f32,
	cur_pos:     [3]f32,

	last_ack:    u32,
	corrections: u64,
	last_error:  f32,
	max_error:   f32,
	replayed:    int,
}

predict_init :: proc(
	p: ^Predictor($I, $S),
	entity: EntityId,
	apply: proc(w: ^World, id: EntityId, input: I, dt: f32),
	restore: proc(w: ^World, id: EntityId, state: S),
	read_pos: proc(w: ^World, id: EntityId) -> [3]f32,
) {
	p.entity = entity
	p.apply = apply
	p.restore = restore
	p.read_pos = read_pos
	p.pending_n = 0
	p.next_seq = 0
	p.primed = false
	p.error = {}
	p.ready = apply != nil && restore != nil && read_pos != nil
}

predict_rebase :: proc(p: ^Predictor($I, $S), entity: EntityId) {
	p.entity = entity
	p.pending_n = 0
	p.primed = false
	p.error = {}
}

predict_step :: proc(p: ^Predictor($I, $S), w: ^World, input: I, dt: f32) -> u32 {
	if !p.ready {return 0}

	seq := p.next_seq
	p.next_seq += 1

	entry := PendingInput(I){seq = seq, input = input}
	if p.pending_n < MAX_PENDING {
		p.pending[p.pending_n] = entry
		p.pending_n += 1
	} else {
		copy(p.pending[:], p.pending[1:])
		p.pending[MAX_PENDING - 1] = entry
	}

	p.prev_pos = p.cur_pos
	p.apply(w, p.entity, input, dt)
	p.cur_pos = p.read_pos(w, p.entity)
	return seq
}

predict_reconcile :: proc(p: ^Predictor($I, $S), w: ^World, state: S, ack_seq: u32, dt: f32) {
	if !p.ready {return}

	before := p.read_pos(w, p.entity)
	p.restore(w, p.entity, state)

	if !p.primed {
		pos := p.read_pos(w, p.entity)
		p.pending_n = 0
		p.error = {}
		p.prev_pos = pos
		p.cur_pos = pos
		p.primed = true
		p.last_ack = ack_seq
		return
	}

	keep := 0
	for i in 0 ..< p.pending_n {
		if p.pending[i].seq > ack_seq {
			p.pending[keep] = p.pending[i]
			keep += 1
		}
	}
	p.pending_n = keep

	p.replayed = p.pending_n
	for i in 0 ..< p.pending_n {
		p.apply(w, p.entity, p.pending[i].input, dt)
	}

	after := p.read_pos(w, p.entity)
	shift := after - p.cur_pos
	p.prev_pos += shift
	p.cur_pos = after

	delta := before - after
	d2 := delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2]
	if d2 > 0.000001 {
		p.error += delta
		p.corrections += 1
		p.last_error = _magnitude(d2)
		if p.last_error > p.max_error {p.max_error = p.last_error}
	}

	p.last_ack = ack_seq
}

predict_decay_error :: proc(p: ^Predictor($I, $S), dt: f32) {
	p.error *= _decay(dt)
}

predict_render_pos :: proc(p: ^Predictor($I, $S), alpha: f32) -> [3]f32 {
	if !p.ready {return {}}
	a := clamp(alpha, 0, 1)
	return p.prev_pos + (p.cur_pos - p.prev_pos) * a + p.error
}

@(private)
_magnitude :: proc(d2: f32) -> f32 {
	return math.sqrt(d2)
}

@(private)
_decay :: proc(dt: f32) -> f32 {
	return math.exp(-dt * ERROR_DECAY_RATE)
}
