package clockwork

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"

MAX_FIELD_DEPTH  :: 4
MAX_ARRAY_FIELDS :: 16

FieldKind :: enum u8 {
	Unsupported,
	Bool,
	Int,
	Uint,
	Float,
	Enum,
	String,
	Group,
}

FieldRef :: struct {
	name:     string,
	path:     string,
	type:     typeid,
	kind:     FieldKind,
	ptr:      rawptr,
	depth:    int,
	editable: bool,
	has_range: bool,
	range_min: f64,
	range_max: f64,
}

comp_type :: proc(w: ^World, ct: ComponentId) -> typeid {
	return w.pools[ct].type
}

comp_name :: proc(w: ^World, ct: ComponentId) -> string {
	p := &w.pools[ct]
	if p.name != "" {return p.name}
	if p.type != nil {return type_label(p.type)}
	return "?"
}

comp_ptr :: proc(w: ^World, id: EntityId, ct: ComponentId) -> rawptr {
	p := &w.pools[ct]
	if p.elem_size == 0 || id < 0 || int(id) >= p.cap {return nil}
	return rawptr(uintptr(p.data) + uintptr(int(id) * p.elem_size))
}

type_label :: proc(t: typeid) -> string {
	ti := type_info_of(t)
	if ti == nil {return "?"}
	#partial switch v in ti.variant {
	case runtime.Type_Info_Named:
		return v.name
	}
	return fmt.tprintf("%v", t)
}

kind_of :: proc(t: typeid) -> FieldKind {
	ti := runtime.type_info_base(type_info_of(t))
	if ti == nil {return .Unsupported}
	#partial switch v in ti.variant {
	case runtime.Type_Info_Boolean:
		return .Bool
	case runtime.Type_Info_Integer:
		return v.signed ? FieldKind.Int : FieldKind.Uint
	case runtime.Type_Info_Float:
		return .Float
	case runtime.Type_Info_Enum:
		return .Enum
	case runtime.Type_Info_String:
		return .String
	case runtime.Type_Info_Struct:
		return .Group
	case runtime.Type_Info_Array:
		return .Group
	}
	return .Unsupported
}

comp_fields :: proc(w: ^World, id: EntityId, ct: ComponentId, allocator := context.temp_allocator) -> []FieldRef {
	out := make([dynamic]FieldRef, allocator)
	base := comp_ptr(w, id, ct)
	if base == nil {return out[:]}
	_walk(&out, comp_name(w, ct), "", base, comp_type(w, ct), 0, false, 0, 0, allocator)
	return out[:]
}

type_fields :: proc(label: string, ptr: rawptr, t: typeid, allocator := context.temp_allocator) -> []FieldRef {
	out := make([dynamic]FieldRef, allocator)
	if ptr == nil {return out[:]}
	_walk(&out, label, "", ptr, t, 0, false, 0, 0, allocator)
	return out[:]
}

@(private)
_walk :: proc(out: ^[dynamic]FieldRef, name, path: string, ptr: rawptr, t: typeid, depth: int, has_range: bool, range_min, range_max: f64, allocator: runtime.Allocator) {
	ti := runtime.type_info_base(type_info_of(t))
	if ti == nil {return}

	#partial switch v in ti.variant {
	case runtime.Type_Info_Struct:
		if depth >= MAX_FIELD_DEPTH {
			_leaf(out, name, path, ptr, t, depth, .Unsupported, has_range, range_min, range_max)
			return
		}
		if depth > 0 {
			_leaf(out, name, path, ptr, t, depth, .Group, has_range, range_min, range_max)
		}
		for i in 0 ..< int(v.field_count) {
			fname := v.names[i]
			fptr := rawptr(uintptr(ptr) + v.offsets[i])
			fpath := depth == 0 ? fname : strings.concatenate({path, ".", fname}, allocator)
			tag := reflect.Struct_Tag(v.tags[i])
			inspect := string(reflect.struct_tag_get(tag, "inspect"))
			if inspect == "hidden" {continue}
			if inspect == "text" && _is_text_buffer(v.types[i].id) {
				_leaf(out, fname, fpath, fptr, v.types[i].id, depth + 1, .String, false, 0, 0)
				out[len(out) - 1].editable = true
				continue
			}
			first := len(out)
			field_has_range, field_min, field_max := _field_range(tag)
			_walk(out, fname, fpath, fptr, v.types[i].id, depth + 1, field_has_range, field_min, field_max, allocator)
			if inspect == "readonly" {
				for &f in out[first:] {f.editable = false}
			}
		}
		return

	case runtime.Type_Info_Array:
		ek := kind_of(v.elem.id)
		if ek == .Group || ek == .Unsupported || v.count > MAX_ARRAY_FIELDS || depth >= MAX_FIELD_DEPTH {
			_leaf(out, name, path, ptr, t, depth, .Unsupported, has_range, range_min, range_max)
			return
		}
		_leaf(out, name, path, ptr, t, depth, .Group, has_range, range_min, range_max)
		for i in 0 ..< v.count {
			iname := fmt.aprintf("[%d]", i, allocator = allocator)
			iptr := rawptr(uintptr(ptr) + uintptr(i * v.elem_size))
			ipath := strings.concatenate({path, iname}, allocator)
			_leaf(out, iname, ipath, iptr, v.elem.id, depth + 1, ek, has_range, range_min, range_max)
		}
		return
	}

	_leaf(out, name, path, ptr, t, depth, kind_of(t), has_range, range_min, range_max)
}

@(private)
_leaf :: proc(out: ^[dynamic]FieldRef, name, path: string, ptr: rawptr, t: typeid, depth: int, kind: FieldKind, has_range: bool, range_min, range_max: f64) {
	editable := kind == .Bool || kind == .Int || kind == .Uint || kind == .Float || kind == .Enum
	append(out, FieldRef {
		name     = name,
		path     = path,
		type     = t,
		kind     = kind,
		ptr      = ptr,
		depth    = depth,
		editable = editable,
		has_range = has_range,
		range_min = range_min,
		range_max = range_max,
	})
}

@(private)
_field_range :: proc(tag: reflect.Struct_Tag) -> (has_range: bool, lo, hi: f64) {
	r := string(reflect.struct_tag_get(tag, "range"))
	comma := strings.index_byte(r, ',')
	if comma <= 0 {return}
	ok_lo, ok_hi: bool
	lo, ok_lo = strconv.parse_f64(strings.trim_space(r[:comma]))
	hi, ok_hi = strconv.parse_f64(strings.trim_space(r[comma + 1:]))
	return ok_lo && ok_hi && lo < hi, lo, hi
}

@(private)
_is_text_buffer :: proc(t: typeid) -> bool {
	ti := runtime.type_info_base(type_info_of(t))
	if ti == nil {return false}
	arr, is_array := ti.variant.(runtime.Type_Info_Array)
	if !is_array || arr.elem_size != 1 {return false}
	_, is_int := runtime.type_info_base(arr.elem).variant.(runtime.Type_Info_Integer)
	return is_int
}

@(private)
_text_buffer :: proc(f: FieldRef) -> []u8 {
	ti := runtime.type_info_base(type_info_of(f.type))
	return ([^]u8)(f.ptr)[:ti.size]
}

field_text :: proc(f: FieldRef, allocator := context.temp_allocator) -> string {
	if f.ptr == nil || f.kind == .Group {return ""}
	if f.kind == .String && _is_text_buffer(f.type) {
		buf := _text_buffer(f)
		n := 0
		for n < len(buf) && buf[n] != 0 {n += 1}
		return strings.clone(string(buf[:n]), allocator)
	}
	return fmt.aprintf("%v", any{f.ptr, f.type}, allocator = allocator)
}

field_f64 :: proc(f: FieldRef) -> (value: f64, ok: bool) {
	if f.ptr == nil {return 0, false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Float:
		switch ti.size {
		case 4: return f64((^f32)(f.ptr)^), true
		case 8: return (^f64)(f.ptr)^, true
		}
	case runtime.Type_Info_Integer:
		if v.signed {
			n := _read_i64(f.ptr, ti.size) or_return
			return f64(n), true
		}
		n := _read_u64(f.ptr, ti.size) or_return
		return f64(n), true
	case runtime.Type_Info_Enum:
		n := _read_i64(f.ptr, ti.size) or_return
		return f64(n), true
	case runtime.Type_Info_Boolean:
		b := field_bool(f) or_return
		return b ? 1 : 0, true
	}
	return 0, false
}

field_i64 :: proc(f: FieldRef) -> (value: i64, ok: bool) {
	if f.ptr == nil {return 0, false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Integer:
		if !v.signed {return 0, false}
		return _read_i64(f.ptr, ti.size)
	case runtime.Type_Info_Enum:
		return _read_i64(f.ptr, ti.size)
	}
	return 0, false
}

field_u64 :: proc(f: FieldRef) -> (value: u64, ok: bool) {
	if f.ptr == nil {return 0, false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Integer:
		if v.signed {return 0, false}
		return _read_u64(f.ptr, ti.size)
	}
	return 0, false
}

field_set_f64 :: proc(f: FieldRef, value: f64) -> bool {
	if f.ptr == nil || !f.editable {return false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Float:
		switch ti.size {
		case 4:
			(^f32)(f.ptr)^ = f32(value)
			return true
		case 8:
			(^f64)(f.ptr)^ = value
			return true
		}
	case runtime.Type_Info_Integer:
		if v.signed {return _write_i64(f.ptr, ti.size, i64(value))}
		if value < 0 {return false}
		return _write_u64(f.ptr, ti.size, u64(value))
	case runtime.Type_Info_Enum:
		return _write_i64(f.ptr, ti.size, i64(value))
	case runtime.Type_Info_Boolean:
		return field_set_bool(f, value != 0)
	}
	return false
}

field_set_i64 :: proc(f: FieldRef, value: i64) -> bool {
	if f.ptr == nil || !f.editable {return false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Integer:
		if !v.signed {return false}
		return _write_i64(f.ptr, ti.size, value)
	case runtime.Type_Info_Enum:
		return _write_i64(f.ptr, ti.size, value)
	}
	return false
}

field_set_u64 :: proc(f: FieldRef, value: u64) -> bool {
	if f.ptr == nil || !f.editable {return false}
	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Integer:
		if v.signed {return false}
		return _write_u64(f.ptr, ti.size, value)
	}
	return false
}

field_bool :: proc(f: FieldRef) -> (value: bool, ok: bool) {
	if f.ptr == nil {return false, false}
	ti := runtime.type_info_base(type_info_of(f.type))
	_, is_bool := ti.variant.(runtime.Type_Info_Boolean)
	if !is_bool {return false, false}
	n := _read_u64(f.ptr, ti.size) or_return
	return n != 0, true
}

field_set_bool :: proc(f: FieldRef, value: bool) -> bool {
	if f.ptr == nil {return false}
	ti := runtime.type_info_base(type_info_of(f.type))
	_, is_bool := ti.variant.(runtime.Type_Info_Boolean)
	if !is_bool {return false}
	return _write_u64(f.ptr, ti.size, value ? 1 : 0)
}

enum_names :: proc(t: typeid) -> []string {
	ti := runtime.type_info_base(type_info_of(t))
	if ti == nil {return nil}
	#partial switch v in ti.variant {
	case runtime.Type_Info_Enum:
		return v.names
	}
	return nil
}

enum_values :: proc(t: typeid) -> []runtime.Type_Info_Enum_Value {
	ti := runtime.type_info_base(type_info_of(t))
	if ti == nil {return nil}
	#partial switch v in ti.variant {
	case runtime.Type_Info_Enum:
		return v.values
	}
	return nil
}

field_set_text :: proc(f: FieldRef, text: string) -> bool {
	if f.ptr == nil || !f.editable {return false}
	s := strings.trim_space(text)
	if f.kind == .String && _is_text_buffer(f.type) {
		buf := _text_buffer(f)
		n := min(len(s), len(buf) - 1)
		copy(buf[:n], s[:n])
		for i in n ..< len(buf) {buf[i] = 0}
		return true
	}
	if len(s) == 0 {return false}

	ti := runtime.type_info_base(type_info_of(f.type))
	#partial switch v in ti.variant {
	case runtime.Type_Info_Boolean:
		b, ok := _parse_bool(s)
		if !ok {return false}
		return field_set_bool(f, b)

	case runtime.Type_Info_Float:
		n, ok := strconv.parse_f64(s)
		if !ok {return false}
		return field_set_f64(f, n)

	case runtime.Type_Info_Integer:
		if v.signed {
			n, ok := strconv.parse_i64(s)
			if !ok {return false}
			return _write_i64(f.ptr, ti.size, n)
		}
		n, ok := strconv.parse_u64(s)
		if !ok {return false}
		return _write_u64(f.ptr, ti.size, n)

	case runtime.Type_Info_Enum:
		for name, i in v.names {
			if strings.equal_fold(name, s) {
				return _write_i64(f.ptr, ti.size, i64(v.values[i]))
			}
		}
		n, ok := strconv.parse_i64(s)
		if !ok {return false}
		return _write_i64(f.ptr, ti.size, n)
	}
	return false
}

@(private)
_parse_bool :: proc(s: string) -> (bool, bool) {
	switch {
	case strings.equal_fold(s, "true"), s == "1", strings.equal_fold(s, "on"), strings.equal_fold(s, "yes"):
		return true, true
	case strings.equal_fold(s, "false"), s == "0", strings.equal_fold(s, "off"), strings.equal_fold(s, "no"):
		return false, true
	}
	return false, false
}

@(private)
_read_i64 :: proc(p: rawptr, size: int) -> (i64, bool) {
	switch size {
	case 1: return i64((^i8)(p)^), true
	case 2: return i64((^i16)(p)^), true
	case 4: return i64((^i32)(p)^), true
	case 8: return (^i64)(p)^, true
	}
	return 0, false
}

@(private)
_read_u64 :: proc(p: rawptr, size: int) -> (u64, bool) {
	switch size {
	case 1: return u64((^u8)(p)^), true
	case 2: return u64((^u16)(p)^), true
	case 4: return u64((^u32)(p)^), true
	case 8: return (^u64)(p)^, true
	}
	return 0, false
}

@(private)
_write_i64 :: proc(p: rawptr, size: int, v: i64) -> bool {
	switch size {
	case 1: (^i8)(p)^ = i8(v)
	case 2: (^i16)(p)^ = i16(v)
	case 4: (^i32)(p)^ = i32(v)
	case 8: (^i64)(p)^ = v
	case: return false
	}
	return true
}

@(private)
_write_u64 :: proc(p: rawptr, size: int, v: u64) -> bool {
	switch size {
	case 1: (^u8)(p)^ = u8(v)
	case 2: (^u16)(p)^ = u16(v)
	case 4: (^u32)(p)^ = u32(v)
	case 8: (^u64)(p)^ = v
	case: return false
	}
	return true
}
