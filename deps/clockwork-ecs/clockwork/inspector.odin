package clockwork

import "core:strings"

INSPECTOR_FILTER_CAP :: 64

RowKind :: enum u8 {
	Component,
	Field,
}

InspectorRow :: struct {
	kind:  RowKind,
	comp:  ComponentId,
	label: string,
	field: FieldRef,
	depth: int,
}

Inspector :: struct {
	selected:   EntityId,
	filter:     [INSPECTOR_FILTER_CAP]u8,
	filter_n:   int,
	show_slots: bool,
	collapsed:  Signature,
}

inspector_make :: proc() -> Inspector {
	return Inspector{selected = INVALID_ENTITY}
}

inspector_filter_text :: proc(insp: ^Inspector) -> string {
	return string(insp.filter[:insp.filter_n])
}

inspector_set_filter :: proc(insp: ^Inspector, text: string) {
	n := min(len(text), INSPECTOR_FILTER_CAP)
	copy(insp.filter[:n], text[:n])
	insp.filter_n = n
}

inspector_select :: proc(insp: ^Inspector, w: ^World, id: EntityId) {
	insp.selected = world_is_valid(w, id) ? id : INVALID_ENTITY
}

inspector_validate :: proc(insp: ^Inspector, w: ^World) {
	if !world_is_valid(w, insp.selected) {insp.selected = INVALID_ENTITY}
}

inspector_is_collapsed :: proc(insp: ^Inspector, ct: ComponentId) -> bool {
	return sig_has(insp.collapsed, ct)
}

inspector_toggle_collapsed :: proc(insp: ^Inspector, ct: ComponentId) {
	if sig_has(insp.collapsed, ct) {
		sig_clear(&insp.collapsed, ct)
		return
	}
	sig_set(&insp.collapsed, ct)
}

inspector_editable :: proc(sim: ^Sim) -> bool {
	if sim == nil {return true}
	return sim.role == .Host
}

inspector_authority_note :: proc(sim: ^Sim) -> string {
	if inspector_editable(sim) {return ""}
	return "read-only: this world is not authoritative"
}

inspector_entities :: proc(w: ^World, insp: ^Inspector, allocator := context.temp_allocator) -> []EntityId {
	out := make([dynamic]EntityId, allocator)
	filter := strings.trim_space(inspector_filter_text(insp))

	for i in 0 ..< len(w.entities) {
		if !entity_is_active(w.entities[i]) {continue}
		id := EntityId(i)
		if filter != "" && !_entity_matches(w, id, filter) {continue}
		append(&out, id)
	}
	return out[:]
}

@(private)
_entity_matches :: proc(w: ^World, id: EntityId, filter: string) -> bool {
	if strings.has_prefix(filter, "#") {
		return strings.has_prefix(_id_text(id), strings.trim_prefix(filter, "#"))
	}
	for ct in 0 ..< MAX_COMPONENTS {
		if !sig_has(w.entities[id].signature, ComponentId(ct)) {continue}
		if strings.contains(strings.to_lower(comp_name(w, ComponentId(ct)), context.temp_allocator),
			strings.to_lower(filter, context.temp_allocator)) {
			return true
		}
	}
	return false
}

@(private)
_id_text :: proc(id: EntityId) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_int(&b, int(id))
	return strings.to_string(b)
}

inspector_components :: proc(w: ^World, id: EntityId, allocator := context.temp_allocator) -> []ComponentId {
	out := make([dynamic]ComponentId, allocator)
	if !world_is_valid(w, id) {return out[:]}
	for ct in 0 ..< MAX_COMPONENTS {
		if sig_has(w.entities[id].signature, ComponentId(ct)) {
			append(&out, ComponentId(ct))
		}
	}
	return out[:]
}

inspector_missing_components :: proc(w: ^World, id: EntityId, allocator := context.temp_allocator) -> []ComponentId {
	out := make([dynamic]ComponentId, allocator)
	if !world_is_valid(w, id) {return out[:]}
	for ct in 0 ..< MAX_COMPONENTS {
		if w.pools[ct].elem_size == 0 {continue}
		if sig_has(w.entities[id].signature, ComponentId(ct)) {continue}
		append(&out, ComponentId(ct))
	}
	return out[:]
}

inspector_rows :: proc(w: ^World, insp: ^Inspector, allocator := context.temp_allocator) -> []InspectorRow {
	out := make([dynamic]InspectorRow, allocator)
	id := insp.selected
	if !world_is_valid(w, id) {return out[:]}

	for ct in inspector_components(w, id, allocator) {
		append(&out, InspectorRow {
			kind  = .Component,
			comp  = ct,
			label = comp_name(w, ct),
			depth = 0,
		})
		if inspector_is_collapsed(insp, ct) {continue}

		for f in comp_fields(w, id, ct, allocator) {
			if f.depth == 0 {continue}
			append(&out, InspectorRow {
				kind  = .Field,
				comp  = ct,
				label = f.name,
				field = f,
				depth = f.depth,
			})
		}
	}
	return out[:]
}
