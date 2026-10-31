package clockwork

import "base:intrinsics"
import "core:mem"
import "core:reflect"

Component_Pool :: struct {
	data:      rawptr,
	bitset:    [dynamic]u64,
	elem_size: int,
	type:      typeid,
	ptr_type:  typeid,
	name:      string,
	align:     int,
	cap:       int,
	clear:     proc(rawptr),
	init:      proc(rawptr),

	codec:     Codec,
	transient: bool,
}

pool_is_registered :: proc(p: ^Component_Pool) -> bool {
	return p.elem_size > 0
}

comp_register :: proc(w: ^World, ct: $E, $T: typeid, clear_fn: proc(rawptr) = nil) where intrinsics.type_is_enum(E) {
	comp_register_id(w, comp_id(ct), T, clear_fn)
	w.pools[comp_id(ct)].name = _enum_name(ct)
}

comp_register_id :: proc(w: ^World, ct: ComponentId, $T: typeid, clear_fn: proc(rawptr) = nil) {
	assert(int(ct) < MAX_COMPONENTS)
	p := &w.pools[ct]
	assert(p.elem_size == 0)
	p.elem_size = max(size_of(T), 1)
	p.align = max(align_of(T), 1)
	p.type = T
	p.ptr_type = typeid_of(^T)
	p.clear = clear_fn
	_pool_reserve(p, max(len(w.entities), CHUNK_SIZE))
}

comp_get :: #force_inline proc(w: ^World, id: EntityId, ct: $E, $T: typeid, loc := #caller_location) -> ^T where intrinsics.type_is_enum(E) {
	return comp_get_id(w, id, comp_id(ct), T, loc)
}

comp_get_id :: #force_inline proc(w: ^World, id: EntityId, ct: ComponentId, $T: typeid, loc := #caller_location) -> ^T {
	p := &w.pools[ct]
	assert(p.elem_size == max(size_of(T), 1), "component type does not match the registered pool", loc)
	assert(id >= 0 && int(id) < p.cap, "entity id out of range for component pool", loc)
	return (^T)(rawptr(uintptr(p.data) + uintptr(int(id) * p.elem_size)))
}

comp_set :: #force_inline proc(w: ^World, id: EntityId, ct: $E, val: $T, loc := #caller_location) where intrinsics.type_is_enum(E) {
	comp_set_id(w, id, comp_id(ct), val, loc)
}

comp_set_id :: #force_inline proc(w: ^World, id: EntityId, ct: ComponentId, val: $T, loc := #caller_location) {
	comp_get_id(w, id, ct, T, loc)^ = val
	_comp_mark(w, id, ct)
}

comp_add :: proc(w: ^World, id: EntityId, ct: $E) where intrinsics.type_is_enum(E) {
	comp_add_id(w, id, comp_id(ct))
}

comp_add_id :: proc(w: ^World, id: EntityId, ct: ComponentId) {
	p := &w.pools[ct]
	assert(p.elem_size > 0)
	assert(id >= 0 && int(id) < p.cap)
	if p.init != nil && !sig_has(w.entities[id].signature, ct) {
		p.init(rawptr(uintptr(p.data) + uintptr(int(id) * p.elem_size)))
	}
	_comp_mark(w, id, ct)
}

comp_set_init :: proc(w: ^World, ct: ComponentId, init_fn: proc(rawptr)) {
	w.pools[ct].init = init_fn
}

comp_remove :: proc(w: ^World, id: EntityId, ct: $E) where intrinsics.type_is_enum(E) {
	comp_remove_id(w, id, comp_id(ct))
}

comp_remove_id :: proc(w: ^World, id: EntityId, ct: ComponentId) {
	p := &w.pools[ct]
	assert(p.elem_size > 0)
	if id < 0 || int(id) >= p.cap {return}
	if !sig_has(w.entities[id].signature,ct) {return}
	_pool_clear_slot(p, int(id))
	p.bitset[int(id) >> 6] &~= u64(1) << uint(int(id) & 63)
	sig_clear(&w.entities[id].signature, ct)
}

comp_has :: proc(w: ^World, id: EntityId, ct: $E) -> bool where intrinsics.type_is_enum(E) {
	return comp_has_id(w, id, comp_id(ct))
}

comp_has_id :: proc(w: ^World, id: EntityId, ct: ComponentId) -> bool {
	if !world_is_valid(w, id) {return false}
	return sig_has(w.entities[id].signature, ct)
}

@(private)
_comp_mark :: #force_inline proc(w: ^World, id: EntityId, ct: ComponentId) {
	p := &w.pools[ct]
	p.bitset[int(id) >> 6] |= u64(1) << uint(int(id) & 63)
	sig_set(&w.entities[id].signature, ct)
}

@(private)
_pool_reserve :: proc(p: ^Component_Pool, count: int) {
	if count <= p.cap {return}
	ptr, err := mem.resize(p.data, p.cap * p.elem_size, count * p.elem_size, p.align)
	assert(err == nil)
	p.data = ptr
	p.cap = count
	resize(&p.bitset, (count + 63) / 64)
}

@(private)
_pool_clear_slot :: proc(p: ^Component_Pool, i: int) {
	slot := rawptr(uintptr(p.data) + uintptr(i * p.elem_size))
	if p.clear != nil {
		p.clear(slot)
		return
	}
	mem.zero(slot, p.elem_size)
}

@(private)
_pool_free :: proc(p: ^Component_Pool) {
	if p.data != nil {mem.free(p.data)}
	delete(p.bitset)
	p^ = {}
}

@(private)
_enum_name :: proc(v: any) -> string {
	name, ok := reflect.enum_name_from_value_any(v)
	return ok ? name : ""
}
