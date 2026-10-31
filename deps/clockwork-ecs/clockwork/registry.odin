package clockwork

import "base:intrinsics"
import "core:encoding/json"
import "core:reflect"

// Component ids are allocated in blocks. A module reserves one run for its own
// component enum and keeps the base it gets back; `cid` turns a member of that
// enum into the runtime id. The engine takes the first block, so its own
// `Comp` members keep the ids they always had, and a project's components land
// above them without either side knowing the other's numbering.
//
//	Health :: struct { hp, max: f32 }
//	My_Comp :: enum u8 { Health }
//
//	base: cw.ComponentId
//
//	base = cw.comp_block(w, My_Comp)
//	cw.comp_register_at(w, base, My_Comp.Health, Health)
//	cw.comp_set_id(w, e, cw.cid(base, My_Comp.Health), Health{hp = 100, max = 100})

// Turns a member of a block's enum into its runtime component id.
cid :: #force_inline proc(base: ComponentId, ct: $E) -> ComponentId where intrinsics.type_is_enum(E) {
	return base + ComponentId(ct)
}

// Reserves a run of ids wide enough for every member of E and returns its base.
// Call once per world, in the same order for every world, so the bases a module
// caches stay valid across them.
comp_block :: proc(w: ^World, $E: typeid, loc := #caller_location) -> ComponentId where intrinsics.type_is_enum(E) {
	return comp_block_n(w, _enum_span(E), loc)
}

// Reserves `count` ids and returns the base, for a module that numbers its
// components by hand rather than through an enum.
comp_block_n :: proc(w: ^World, count: int, loc := #caller_location) -> ComponentId {
	assert(count > 0, "a component block needs at least one id", loc)
	assert(int(w.next_block) + count <= MAX_COMPONENTS, "out of component ids: raise MAX_COMPONENTS", loc)
	base := w.next_block
	w.next_block += ComponentId(count)
	return base
}

// Registers a component within a block, taking its inspector name from the enum.
comp_register_at :: proc(
	w: ^World,
	base: ComponentId,
	ct: $E,
	$T: typeid,
	clear_fn: proc(rawptr) = nil,
	loc := #caller_location,
) where intrinsics.type_is_enum(E) {
	id := cid(base, ct)
	assert(int(id) < int(w.next_block), "component id falls outside any reserved block", loc)
	comp_register_id(w, id, T, clear_fn)
	w.pools[id].name = _enum_name(ct)
}

// Every component id that has a pool behind it, in id order.
registered_components :: proc(w: ^World, allocator := context.temp_allocator) -> []ComponentId {
	out := make([dynamic]ComponentId, allocator)
	for ct in 0 ..< MAX_COMPONENTS {
		if w.pools[ct].elem_size == 0 {continue}
		append(&out, ComponentId(ct))
	}
	return out[:]
}

// Resolves a component by the name the inspector shows for it.
comp_by_name :: proc(w: ^World, name: string) -> (ct: ComponentId, ok: bool) {
	for i in 0 ..< MAX_COMPONENTS {
		if w.pools[i].elem_size == 0 {continue}
		if comp_name(w, ComponentId(i)) == name {return ComponentId(i), true}
	}
	return 0, false
}

// Serialisation
//
// A component round-trips through JSON with no per-type code: `comp_marshal`
// reflects over whatever struct was registered. A component that holds runtime
// handles rather than plain data needs those resolved on the way in and out,
// so it can install its own pair with `comp_set_codec` instead.

Codec :: struct {
	// Both are optional; a nil field falls back to reflection over the struct.
	// `marshal` returns bytes owned by the temp allocator.
	marshal:   proc(w: ^World, id: EntityId, ct: ComponentId) -> ([]byte, bool),
	unmarshal: proc(w: ^World, id: EntityId, ct: ComponentId, data: []byte) -> bool,
}

comp_set_codec :: proc(w: ^World, ct: ComponentId, codec: Codec) {
	w.pools[ct].codec = codec
}

// Marks a component as runtime-only, so level save skips it. Use it for state
// that is rebuilt on load rather than stored -- caches, resolved links, the
// bookkeeping a system keeps between frames.
comp_set_transient :: proc(w: ^World, ct: ComponentId, transient: bool = true) {
	w.pools[ct].transient = transient
}

comp_is_transient :: proc(w: ^World, ct: ComponentId) -> bool {
	return w.pools[ct].transient
}

// Serialises one component of one entity. Bytes come from the temp allocator.
comp_marshal :: proc(w: ^World, id: EntityId, ct: ComponentId) -> ([]byte, bool) {
	p := &w.pools[ct]
	if p.elem_size == 0 {return nil, false}
	if p.codec.marshal != nil {return p.codec.marshal(w, id, ct)}

	ptr := comp_ptr(w, id, ct)
	if ptr == nil {return nil, false}
	data, err := json.marshal(any{ptr, p.type}, {}, context.temp_allocator)
	if err != nil {return nil, false}
	return data, true
}

// Applies serialised bytes onto one component of one entity, and marks the
// component present on it.
comp_unmarshal :: proc(w: ^World, id: EntityId, ct: ComponentId, data: []byte) -> bool {
	p := &w.pools[ct]
	if p.elem_size == 0 {return false}
	if p.codec.unmarshal != nil {
		if !p.codec.unmarshal(w, id, ct, data) {return false}
		_comp_mark(w, id, ct)
		return true
	}

	// `unmarshal_any` wants an `any` that describes a pointer to the target, not
	// the target itself, so hand it the slot address through the pool's `^T`.
	slot := comp_ptr(w, id, ct)
	if slot == nil {return false}
	if json.unmarshal_any(data, any{&slot, p.ptr_type}, json.DEFAULT_SPECIFICATION, context.temp_allocator) != nil {
		return false
	}
	_comp_mark(w, id, ct)
	return true
}

@(private)
_enum_span :: proc($E: typeid) -> int where intrinsics.type_is_enum(E) {
	hi := -1
	for v in reflect.enum_field_values(E) {
		if int(v) > hi {hi = int(v)}
	}
	return hi + 1
}

_ :: reflect
