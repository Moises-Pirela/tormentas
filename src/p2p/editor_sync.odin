package p2p

import "core:mem"

EditorOpAction :: enum u8 {
    Paint         = 1,
    Erase         = 2,
    ClearAll      = 3,
    EraseObjects  = 4,
    FillWalkable  = 5,
}

EditorOp :: struct #packed {
    action:       EditorOpAction,
    brush:        u8,
    tx:           i16,
    ty:           i16,
    target_level: u16,
}

EDITOR_OP_SIZE :: size_of(EditorOp)

EditorModOp :: struct #packed {
    tx:    i16,
    ty:    i16,
    kind:  u8,
    field: u8,
    value: u32,
}

EDITOR_MOD_OP_SIZE :: size_of(EditorModOp)

session_send_editor_op :: proc(s: ^Session, op: EditorOp) {
    if s.state != .Connected { return }
    op := op
    pkt: [1 + EDITOR_OP_SIZE]u8
    pkt[0] = u8(MsgType.EditorOp)
    mem.copy(&pkt[1], &op, EDITOR_OP_SIZE)
    _send(s, pkt[:])
}

session_send_level_load :: proc(s: ^Session, n: int) {
    if s.state != .Connected { return }
    n16 := u16(n)
    pkt: [3]u8
    pkt[0] = u8(MsgType.LevelLoad)
    pkt[1] = u8(n16)
    pkt[2] = u8(n16 >> 8)
    _send(s, pkt[:])
}

session_send_editor_mod_op :: proc(s: ^Session, op: EditorModOp) {
    if s.state != .Connected { return }
    op := op
    pkt: [1 + EDITOR_MOD_OP_SIZE]u8
    pkt[0] = u8(MsgType.EditorModOp)
    mem.copy(&pkt[1], &op, EDITOR_MOD_OP_SIZE)
    _send(s, pkt[:])
}

session_drain_editor_mod_ops :: proc(s: ^Session) -> []EditorModOp {
    if len(s.editor_mod_ops) == 0 { return nil }
    ops := make([]EditorModOp, len(s.editor_mod_ops), context.temp_allocator)
    copy(ops, s.editor_mod_ops[:])
    clear(&s.editor_mod_ops)
    return ops
}

session_drain_editor :: proc(s: ^Session) -> (ops: []EditorOp, load_level: int) {
    if len(s.editor_ops) > 0 {
        ops = make([]EditorOp, len(s.editor_ops), context.temp_allocator)
        copy(ops, s.editor_ops[:])
        clear(&s.editor_ops)
    }
    load_level           = s.pending_level_load
    s.pending_level_load = 0
    return
}

@(private)
_handle_editor_op :: proc(s: ^Session, payload: []u8) {
    if len(payload) < EDITOR_OP_SIZE { return }
    op: EditorOp
    mem.copy(&op, raw_data(payload), EDITOR_OP_SIZE)
    append(&s.editor_ops, op)
}

@(private)
_handle_editor_mod_op :: proc(s: ^Session, payload: []u8) {
    if len(payload) < EDITOR_MOD_OP_SIZE { return }
    op: EditorModOp
    mem.copy(&op, raw_data(payload), EDITOR_MOD_OP_SIZE)
    append(&s.editor_mod_ops, op)
}

@(private)
_handle_level_load_msg :: proc(s: ^Session, payload: []u8) {
    if len(payload) < 2 { return }
    n := int(u16(payload[0]) | u16(payload[1]) << 8)
    if n > 0 { s.pending_level_load = n }
}
