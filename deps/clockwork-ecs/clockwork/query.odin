package clockwork

import "base:intrinsics"

Query :: struct {
	w:        ^World,
	mask:     Signature,
	word_idx: int,
	base:     int,
	cur_word: u64,
}

query_iter :: proc(w: ^World, m: Signature) -> Query {
	return Query{w = w, mask = m}
}

query_next :: proc(q: ^Query) -> (id: EntityId, ok: bool) {
	for {
		for q.cur_word != 0 {
			bit := int(intrinsics.count_trailing_zeros(q.cur_word))
			q.cur_word &= q.cur_word - 1
			eid := q.base + bit
			if eid < len(q.w.entities) && query_visible(q.w.entities[eid]) {
				return EntityId(eid), true
			}
		}

		words := (len(q.w.entities) + 63) / 64
		if q.word_idx >= words {return INVALID_ENTITY, false}

		combined := ~u64(0)
		for cm := u128(q.mask); cm != 0; cm &= cm - 1 {
			ct := int(intrinsics.count_trailing_zeros(cm))
			p := &q.w.pools[ct]
			if q.word_idx >= len(p.bitset) {
				combined = 0
				break
			}
			combined &= p.bitset[q.word_idx]
		}

		q.base = q.word_idx * 64
		q.word_idx += 1
		q.cur_word = combined
	}
}

query_collect :: proc(w: ^World, m: Signature, allocator := context.allocator) -> []EntityId {
	out := make([dynamic]EntityId, allocator)
	q := query_iter(w, m)
	for {
		id, ok := query_next(&q)
		if !ok {break}
		append(&out, id)
	}
	return out[:]
}

mask :: proc(types: []$E) -> Signature where intrinsics.type_is_enum(E) {
	m := Signature(0)
	for t in types {
		m |= Signature(1) << uint(comp_id(t))
	}
	return m
}

mask_ids :: proc(types: ..ComponentId) -> Signature {
	m := Signature(0)
	for t in types {
		m |= Signature(1) << uint(t)
	}
	return m
}

// Queries skip an entity the moment it is marked for destruction, so a system
// never acts on something already on its way out. It stays readable by id until
// the sweep, which is what makes `.EntityDestroyed` useful.
query_visible :: #force_inline proc(e: Entity) -> bool {
	return entity_is_active(e) && .ToDestroy not_in e.flags
}
