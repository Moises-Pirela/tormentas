package clockwork

import "base:intrinsics"

EntityFlag :: enum u8 {
	Active,
	Dead,
	ToDestroy,
}

EntityFlags :: distinct bit_set[EntityFlag;u8]

Signature :: distinct u128

Entity :: struct {
	id:        EntityId,
	flags:     EntityFlags,
	signature: Signature,
}

entity_empty :: proc() -> Entity {
	return Entity{id = INVALID_ENTITY}
}

entity_is_active :: proc(e: Entity) -> bool {
	return .Active in e.flags
}

comp_id :: #force_inline proc(ct: $E) -> ComponentId where intrinsics.type_is_enum(E) {
	return ComponentId(ct)
}

sig_set :: proc(sig: ^Signature, ct: ComponentId) {
	sig^ |= Signature(1) << uint(ct)
}

sig_clear :: proc(sig: ^Signature, ct: ComponentId) {
	sig^ &~= Signature(1) << uint(ct)
}

sig_has :: proc(sig: Signature, ct: ComponentId) -> bool {
	return (sig & (Signature(1) << uint(ct))) != 0
}
