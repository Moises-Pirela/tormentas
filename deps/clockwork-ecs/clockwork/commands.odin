package clockwork

import "core:strconv"
import "core:strings"

console_register_builtins :: proc(c: ^Console) {
	console_register(c, "help", "list commands, or 'help <cmd>'", cmd_help)
	console_register(c, "clear", "clear the log", cmd_clear)
	console_register(c, "ent", "list live entities", cmd_ent)
	console_register(c, "spawn", "create an entity", cmd_spawn)
	console_register(c, "destroy", "destroy <id>", cmd_destroy)
	console_register(c, "comp", "comp <id> -- list components on an entity", cmd_comp)
	console_register(c, "comps", "list registered component types", cmd_comps)
	console_register(c, "get", "get <id> <comp> [field]", cmd_get)
	console_register(c, "set", "set <id> <comp> <field> <value>", cmd_set)
	console_register(c, "add", "add <id> <comp>", cmd_add)
	console_register(c, "rm", "rm <id> <comp>", cmd_rm)
	console_register(c, "world", "world summary", cmd_world)
}

@(private)
cmd_help :: proc(c: ^Console, w: ^World, args: string) {
	topic := strings.trim_space(args)
	if topic == "" {
		console_log(c, "commands:")
		for cmd in c.commands {
			console_logf(c, "  %-10s %s", cmd.name, cmd.help)
		}
		return
	}
	cmd, ok := console_find(c, topic)
	if !ok {
		console_errorf(c, "no such command '%s'", topic)
		return
	}
	console_logf(c, "%s -- %s", cmd.name, cmd.help)
}

@(private)
cmd_clear :: proc(c: ^Console, w: ^World, args: string) {
	console_clear(c)
}

@(private)
cmd_world :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	registered := 0
	for &p in w.pools {
		if p.elem_size > 0 {registered += 1}
	}
	console_logf(c, "tick %d   entities %d live / %d slots   components %d   pending destroy %d",
		w.tick, world_entity_count(w), len(w.entities), registered, len(w.pending_destroy))
}

@(private)
cmd_comps :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	for ct in 0 ..< MAX_COMPONENTS {
		p := &w.pools[ct]
		if p.elem_size == 0 {continue}
		console_logf(c, "  %3d  %-20s %s (%d bytes)",
			ct, comp_name(w, ComponentId(ct)), type_label(p.type), p.elem_size)
	}
}

@(private)
cmd_ent :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	shown := 0
	for i in 0 ..< len(w.entities) {
		if !entity_is_active(w.entities[i]) {continue}
		if shown >= 64 {
			console_warnf(c, "... %d more", world_entity_count(w) - shown)
			break
		}
		shown += 1
		console_logf(c, "  #%d  %s", i, _comp_summary(w, EntityId(i)))
	}
	if shown == 0 {console_log(c, "no live entities")}
}

@(private)
_comp_summary :: proc(w: ^World, id: EntityId) -> string {
	b := strings.builder_make(context.temp_allocator)
	first := true
	for ct in 0 ..< MAX_COMPONENTS {
		if !sig_has(w.entities[id].signature, ComponentId(ct)) {continue}
		if !first {strings.write_string(&b, ", ")}
		strings.write_string(&b, comp_name(w, ComponentId(ct)))
		first = false
	}
	if first {return "(no components)"}
	return strings.to_string(b)
}

console_lookup_comp :: proc(w: ^World, name: string) -> (ct: ComponentId, ok: bool) {
	if n, parsed := strconv.parse_int(name); parsed {
		if n >= 0 && n < MAX_COMPONENTS && w.pools[n].elem_size > 0 {
			return ComponentId(n), true
		}
		return 0, false
	}
	for i in 0 ..< MAX_COMPONENTS {
		if w.pools[i].elem_size == 0 {continue}
		if strings.equal_fold(comp_name(w, ComponentId(i)), name) {
			return ComponentId(i), true
		}
	}
	return 0, false
}

@(private)
_arg_entity :: proc(c: ^Console, w: ^World, raw: string) -> (id: EntityId, ok: bool) {
	n, parsed := strconv.parse_int(strings.trim_prefix(raw, "#"))
	if !parsed {
		console_errorf(c, "'%s' is not an entity id", raw)
		return 0, false
	}
	if !world_is_valid(w, EntityId(n)) {
		console_errorf(c, "entity #%d is not live", n)
		return 0, false
	}
	return EntityId(n), true
}

@(private)
_arg_comp :: proc(c: ^Console, w: ^World, raw: string) -> (ct: ComponentId, ok: bool) {
	ct, ok = console_lookup_comp(w, raw)
	if !ok {console_errorf(c, "no registered component '%s' -- try 'comps'", raw)}
	return
}

@(private)
cmd_spawn :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	id := world_create_entity(w)
	console_goodf(c, "spawned #%d", id)
}

@(private)
cmd_destroy :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	id, ok := _arg_entity(c, w, strings.trim_space(args))
	if !ok {return}
	world_mark_destroy(w, id)
	console_goodf(c, "destroyed #%d (cleared on next sweep)", id)
}

@(private)
cmd_comp :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	id, ok := _arg_entity(c, w, strings.trim_space(args))
	if !ok {return}
	console_logf(c, "#%d: %s", id, _comp_summary(w, id))
}

@(private)
cmd_add :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	ent_s, rest := console_arg(args)
	id, ok := _arg_entity(c, w, ent_s)
	if !ok {return}
	ct, cok := _arg_comp(c, w, strings.trim_space(rest))
	if !cok {return}
	comp_add_id(w, id, ct)
	console_goodf(c, "#%d += %s", id, comp_name(w, ct))
}

@(private)
cmd_rm :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	ent_s, rest := console_arg(args)
	id, ok := _arg_entity(c, w, ent_s)
	if !ok {return}
	ct, cok := _arg_comp(c, w, strings.trim_space(rest))
	if !cok {return}
	comp_remove_id(w, id, ct)
	console_goodf(c, "#%d -= %s", id, comp_name(w, ct))
}

@(private)
cmd_get :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	ent_s, rest := console_arg(args)
	id, ok := _arg_entity(c, w, ent_s)
	if !ok {return}

	comp_s, field_s := console_arg(rest)
	ct, cok := _arg_comp(c, w, comp_s)
	if !cok {return}

	if !comp_has_id(w, id, ct) {
		console_warnf(c, "#%d has no %s", id, comp_name(w, ct))
		return
	}

	want := strings.trim_space(field_s)
	fields := comp_fields(w, id, ct)
	hits := 0
	for f in fields {
		if f.kind == .Group {continue}
		if want != "" && !strings.equal_fold(f.path, want) {continue}
		hits += 1
		console_logf(c, "  %-24s %s", f.path, field_text(f))
	}
	if hits == 0 {
		if want == "" {
			console_warnf(c, "%s has no readable fields", comp_name(w, ct))
			return
		}
		console_errorf(c, "no field '%s' on %s", want, comp_name(w, ct))
	}
}

@(private)
cmd_set :: proc(c: ^Console, w: ^World, args: string) {
	if w == nil {
		console_error(c, "no world bound")
		return
	}
	ent_s, r1 := console_arg(args)
	id, ok := _arg_entity(c, w, ent_s)
	if !ok {return}

	comp_s, r2 := console_arg(r1)
	ct, cok := _arg_comp(c, w, comp_s)
	if !cok {return}

	field_s, value_s := console_arg(r2)
	if field_s == "" || value_s == "" {
		console_error(c, "usage: set <id> <comp> <field> <value>")
		return
	}

	if !comp_has_id(w, id, ct) {
		console_warnf(c, "#%d has no %s", id, comp_name(w, ct))
		return
	}

	fields := comp_fields(w, id, ct)
	for f in fields {
		if !strings.equal_fold(f.path, field_s) {continue}
		if !f.editable {
			console_errorf(c, "%s is not editable (%v)", f.path, f.kind)
			return
		}
		if !field_set_text(f, value_s) {
			console_errorf(c, "could not parse '%s' as %s", value_s, type_label(f.type))
			return
		}
		console_goodf(c, "#%d %s.%s = %s", id, comp_name(w, ct), f.path, field_text(f))
		return
	}
	console_errorf(c, "no field '%s' on %s", field_s, comp_name(w, ct))
}
