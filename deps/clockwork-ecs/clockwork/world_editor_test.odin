package clockwork

import "core:testing"

Inspector_Test_Value :: struct {
	bounded: f32 `range:"0,1"`,
	signed:   i64,
	unsigned: u64,
}

@(test)
editor_restore_preserves_stable_id :: proc(t: ^testing.T) {
	w := make_world()
	defer destroy_world(&w)

	id := world_create_entity(&w)
	world_mark_destroy(&w, id)
	testing.expect(t, !world_restore_entity(&w, id), "an unswept entity is revived in place")
	testing.expect(t, world_is_valid(&w, id))
	testing.expect(t, len(world_pending_destroy(&w)) == 0)

	world_mark_destroy(&w, id)
	world_sweep(&w)
	testing.expect(t, !world_is_valid(&w, id))
	testing.expect(t, world_restore_entity(&w, id), "a swept entity is recreated with the same id")
	testing.expect(t, world_is_valid(&w, id))

	next := world_create_entity(&w)
	testing.expect(t, next != id, "restoration must not leave the id available for reuse")
}

@(test)
inspector_numeric_fields_keep_type_and_range :: proc(t: ^testing.T) {
	value := Inspector_Test_Value{
		bounded = 0.5,
		signed = -9_007_199_254_740_993,
		unsigned = 18_446_744_073_709_551_000,
	}
	fields := type_fields("test", rawptr(&value), typeid_of(Inspector_Test_Value))
	testing.expect(t, len(fields) == 3)
	testing.expect(t, fields[0].has_range && fields[0].range_min == 0 && fields[0].range_max == 1)

	signed, signed_ok := field_i64(fields[1])
	unsigned, unsigned_ok := field_u64(fields[2])
	testing.expect(t, signed_ok && signed == value.signed)
	testing.expect(t, unsigned_ok && unsigned == value.unsigned)

	testing.expect(t, field_set_i64(fields[1], -9_007_199_254_740_995))
	testing.expect(t, field_set_u64(fields[2], 18_446_744_073_709_551_002))
	testing.expect(t, value.signed == -9_007_199_254_740_995)
	testing.expect(t, value.unsigned == 18_446_744_073_709_551_002)
}

Inspector_Tag_Value :: struct {
	name:    [32]u8 `inspect:"text"`,
	shown:   u32,
	locked:  u32 `inspect:"readonly"`,
	secret:  u32 `inspect:"hidden"`,
}

@(test)
inspector_tags_shape_fields :: proc(t: ^testing.T) {
	value := Inspector_Tag_Value{shown = 1, locked = 2, secret = 3}
	fields := type_fields("test", rawptr(&value), typeid_of(Inspector_Tag_Value))
	testing.expect_value(t, len(fields), 3)
	testing.expect(t, fields[0].kind == .String && fields[0].editable)
	testing.expect(t, fields[1].editable)
	testing.expect(t, !fields[2].editable)
	for f in fields {testing.expect(t, f.name != "secret")}

	testing.expect(t, field_set_text(fields[0], "audio/sfx/fire_loop.ogg"))
	testing.expect_value(t, field_text(fields[0]), "audio/sfx/fire_loop.ogg")
	testing.expect(t, field_set_text(fields[0], "short"))
	testing.expect_value(t, field_text(fields[0]), "short")
	testing.expect(t, value.name[5] == 0 && value.name[20] == 0)
	testing.expect(t, field_set_text(fields[0], ""))
	testing.expect_value(t, field_text(fields[0]), "")

	long := "0123456789012345678901234567890123456789"
	testing.expect(t, field_set_text(fields[0], long))
	testing.expect_value(t, field_text(fields[0]), long[:31])
	testing.expect(t, !field_set_text(fields[2], "9"))
}

@(private)
test_tag_init :: proc(slot: rawptr) {
	(^Inspector_Tag_Value)(slot)^ = Inspector_Tag_Value{shown = 7}
}

@(test)
comp_add_runs_init_once :: proc(t: ^testing.T) {
	w := make_world()
	defer destroy_world(&w)

	ct := comp_block_n(&w, 1)
	comp_register_id(&w, ct, Inspector_Tag_Value)
	comp_set_init(&w, ct, test_tag_init)

	id := world_create_entity(&w)
	comp_add_id(&w, id, ct)
	v := comp_get_id(&w, id, ct, Inspector_Tag_Value)
	testing.expect_value(t, v.shown, 7)

	v.shown = 9
	comp_add_id(&w, id, ct)
	testing.expect_value(t, v.shown, 9)
}
