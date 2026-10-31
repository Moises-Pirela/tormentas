package clockwork

INPUT_QUEUE :: 8

PendingInput :: struct($I: typeid) {
	seq:   u32,
	input: I,
}

InputQueue :: struct($I: typeid) {
	active:       bool,
	inbox:        [INPUT_QUEUE]PendingInput(I),
	inbox_n:      int,
	last_applied: I,
	last_seq:     u32,
	has_input:    bool,
}

queue_reset :: proc(q: ^InputQueue($I)) {
	q^ = {}
}

queue_input :: proc(q: ^InputQueue($I), seq: u32, input: I) {
	if q.has_input && seq <= q.last_seq {return}

	for i in 0 ..< q.inbox_n {
		if q.inbox[i].seq == seq {return}
	}

	if q.inbox_n >= INPUT_QUEUE {
		copy(q.inbox[:], q.inbox[1:])
		q.inbox_n -= 1
	}
	q.inbox[q.inbox_n] = PendingInput(I){seq = seq, input = input}
	q.inbox_n += 1
}

next_input :: proc(q: ^InputQueue($I)) -> (input: I, seq: u32, fresh: bool) {
	if q.inbox_n == 0 {
		return q.last_applied, q.last_seq, false
	}

	p := q.inbox[0]
	copy(q.inbox[:], q.inbox[1:])
	q.inbox_n -= 1

	q.last_applied = p.input
	q.last_seq = p.seq
	q.has_input = true
	return p.input, p.seq, true
}

queue_backlog :: proc(q: ^InputQueue($I)) -> int {
	return q.inbox_n
}

min_backlog :: proc(qs: []InputQueue($I)) -> int {
	depth := max(int)
	seen := false
	for &q in qs {
		if !q.active || !q.has_input {continue}
		seen = true
		depth = min(depth, q.inbox_n)
	}
	return seen ? depth : 0
}
