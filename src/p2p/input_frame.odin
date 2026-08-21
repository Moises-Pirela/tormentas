package p2p

import "core:mem"

InputAction :: enum u8 {
    Fire,
    Reload,
    Dodge,
    Skill1,
    Skill2,
    Skill3,
    Skill4,
    Interact,
}

InputFrame :: struct {
    tick:    u32,
    peer:    u8,
    actions: bit_set[InputAction; u8],
    _pad:    u16,
    move:    [2]f32,
    aim:     [2]f32,
}

INPUT_FRAME_SIZE :: size_of(InputFrame)

encode_frame :: proc(f: InputFrame, dst: []u8) {
    assert(len(dst) >= INPUT_FRAME_SIZE)
    f := f
    mem.copy(raw_data(dst), &f, INPUT_FRAME_SIZE)
}

decode_frame :: proc(src: []u8) -> (f: InputFrame, ok: bool) {
    if len(src) < INPUT_FRAME_SIZE { return {}, false }
    mem.copy(&f, raw_data(src), INPUT_FRAME_SIZE)
    return f, true
}
