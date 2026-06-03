package p2p

import "core:mem"

MAX_PLAYERS    :: 2
INPUT_DELAY    :: 2
INPUT_BUF_SIZE :: 16

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

InputBuffer :: struct {
    frames: [MAX_PLAYERS][INPUT_BUF_SIZE]InputFrame,
    ready:  [MAX_PLAYERS][INPUT_BUF_SIZE]bool,
}

input_buf_put :: proc(buf: ^InputBuffer, f: InputFrame) {
    p    := int(f.peer) & (MAX_PLAYERS - 1)
    slot := int(f.tick) & (INPUT_BUF_SIZE - 1)
    buf.frames[p][slot] = f
    buf.ready[p][slot]  = true
}

input_buf_get :: proc(buf: ^InputBuffer, peer: int, tick: u32) -> (frame: InputFrame, ok: bool) {
    slot := int(tick) & (INPUT_BUF_SIZE - 1)
    if buf.ready[peer][slot] && buf.frames[peer][slot].tick == tick {
        return buf.frames[peer][slot], true
    }
    return {}, false
}

input_buf_evict :: proc(buf: ^InputBuffer, tick: u32) {
    for p in 0..<MAX_PLAYERS {
        slot := int(tick) & (INPUT_BUF_SIZE - 1)
        if buf.frames[p][slot].tick == tick {
            buf.ready[p][slot] = false
        }
    }
}

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
