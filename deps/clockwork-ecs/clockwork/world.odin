package clockwork

World :: struct {
	entities:        [dynamic]Entity,
	recycled_ids:    [dynamic]EntityId,
	pending_destroy: [dynamic]EntityId,
	// Ids created since the last `.EntityCreated` dispatch.
	created:         [dynamic]EntityId,

	pools:           [MAX_COMPONENTS]Component_Pool,

	next_id:         EntityId,
	last_created:    EntityId,
	next_block:      ComponentId,
	tick:            u64,

	// Whether swept ids are handed back out. Off by default: `EntityId` carries
	// no generation, so a reused id makes a stale reference silently point at a
	// different entity instead of reading as invalid. Turn it on only if nothing
	// in the project stores entity ids across frames.
	recycle_ids:     bool,

	user:            rawptr,
}

make_world :: proc(user: rawptr = nil) -> World {
	w := World{}
	w.user = user
	w.next_id = 0
	w.last_created = INVALID_ENTITY
	resize(&w.entities, CHUNK_SIZE)
	for i in 0 ..< CHUNK_SIZE {w.entities[i] = entity_empty()}
	return w
}

destroy_world :: proc(w: ^World) {
	world_reset(w)
	delete(w.entities)
	delete(w.recycled_ids)
	delete(w.pending_destroy)
	delete(w.created)
	for &p in w.pools {_pool_free(&p)}
	w^ = {}
}

world_create_entity :: proc(w: ^World) -> EntityId {
	id: EntityId
	if len(w.recycled_ids) > 0 {
		id = pop(&w.recycled_ids)
	} else {
		id = w.next_id
		w.next_id += 1
	}

	world_ensure_capacity(w, id)

	w.entities[id] = Entity {
		id    = id,
		flags = {.Active},
	}
	w.last_created = id
	append(&w.created, id)
	return id
}

// Restores an exact id for editor undo/redo. If destruction has not swept yet,
// this simply cancels it and preserves every component in place.
world_restore_entity :: proc(w: ^World, id: EntityId) -> (created: bool) {
	if id < 0 {return false}
	world_ensure_capacity(w, id)
	if entity_is_active(w.entities[id]) {
		if .ToDestroy in w.entities[id].flags {
			w.entities[id].flags -= {.ToDestroy}
			for pending, i in w.pending_destroy {
				if pending == id {
					ordered_remove(&w.pending_destroy, i)
					break
				}
			}
		}
		return false
	}

	w.entities[id] = Entity{id = id, flags = {.Active}}
	for recycled, ri in w.recycled_ids {
		if recycled == id {ordered_remove(&w.recycled_ids, ri); break}
	}
	if id >= w.next_id {w.next_id = id + 1}
	w.last_created = id
	append(&w.created, id)
	return true
}

// Clears an entity's owned components while preserving its stable id. Editor
// history uses this before rebuilding a component snapshot so resource clear
// callbacks run and handles are never silently overwritten.
world_rebuild_entity :: proc(w: ^World, id: EntityId) -> bool {
	if !world_is_valid(w, id) {return false}
	i := int(id)
	sig := w.entities[i].signature
	word := i >> 6
	bit := uint(i & 63)
	for ct in 0 ..< MAX_COMPONENTS {
		if !sig_has(sig, ComponentId(ct)) {continue}
		p := &w.pools[ct]
		if p.elem_size == 0 || i >= p.cap {continue}
		_pool_clear_slot(p, i)
		p.bitset[word] &~= u64(1) << bit
	}
	w.entities[i].signature = {}
	w.entities[i].flags = {.Active}
	for pending, pi in w.pending_destroy {
		if pending == id {ordered_remove(&w.pending_destroy, pi); break}
	}
	append(&w.created, id)
	return true
}

world_mark_destroy :: proc(w: ^World, id: EntityId) {
	if id < 0 || int(id) >= len(w.entities) {return}
	e := &w.entities[id]
	if !entity_is_active(e^) {return}
	if .ToDestroy in e.flags {return}
	// `.Active` stays on until the sweep so an `.EntityDestroyed` system can
	// still read the entity it is being told about. Queries skip it from here.
	e.flags += {.ToDestroy}
	append(&w.pending_destroy, id)
}

world_is_valid :: proc(w: ^World, id: EntityId) -> bool {
	if id < 0 || int(id) >= len(w.entities) {return false}
	return entity_is_active(w.entities[id])
}

world_entity_count :: proc(w: ^World) -> int {
	n := 0
	for e in w.entities {
		if entity_is_active(e) {n += 1}
	}
	return n
}

world_ensure_capacity :: proc(w: ^World, id: EntityId) {
	if int(id) < len(w.entities) {return}
	target := ((int(id) / CHUNK_SIZE) + 1) * CHUNK_SIZE
	old := len(w.entities)
	resize(&w.entities, target)
	for i in old ..< target {w.entities[i] = entity_empty()}
	for &p in w.pools {
		if p.elem_size == 0 {continue}
		_pool_reserve(&p, target)
	}
}

world_sweep :: proc(w: ^World) {
	if len(w.pending_destroy) == 0 {return}
	for id in w.pending_destroy {
		i := int(id)
		if i >= len(w.entities) {continue}
		if .ToDestroy not_in w.entities[i].flags {continue}

		sig := w.entities[i].signature
		word := i >> 6
		bit := uint(i & 63)
		for ct in 0 ..< MAX_COMPONENTS {
			if !sig_has(sig, ComponentId(ct)) {continue}
			p := &w.pools[ct]
			if p.elem_size == 0 || i >= p.cap {continue}
			_pool_clear_slot(p, i)
			p.bitset[word] &~= u64(1) << bit
		}

		w.entities[i] = entity_empty()
		if w.recycle_ids {
			append(&w.recycled_ids, EntityId(i))
		}
	}
	clear(&w.pending_destroy)
}

world_reset :: proc(w: ^World) {
	for i in 0 ..< len(w.entities) {
		if entity_is_active(w.entities[i]) {
			world_mark_destroy(w, EntityId(i))
		}
	}
	world_sweep(w)

	clear(&w.recycled_ids)
	clear(&w.created)
	w.next_id = 0
	w.last_created = INVALID_ENTITY
	w.tick = 0
}

// Entities created since the last `.EntityCreated` dispatch. Valid to read from
// an `.EntityCreated` system.
world_created :: proc(w: ^World) -> []EntityId {
	return w.created[:]
}

// Entities marked for destruction and not yet swept. Valid to read from an
// `.EntityDestroyed` system, where they are still alive and their components
// still readable.
world_pending_destroy :: proc(w: ^World) -> []EntityId {
	return w.pending_destroy[:]
}
