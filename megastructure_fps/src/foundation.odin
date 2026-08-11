package main

TICK_RATE :: 60
TICK_DT   :: f32(1.0 / TICK_RATE)

Id :: distinct u32

INVALID_ID :: Id(0)

Seed_Stream :: struct {
    state: u64,
}

seed_stream_make :: proc(seed: u64) -> Seed_Stream {
    state := seed
    if state == 0 {
        state = 0x9E3779B97F4A7C15
    }
    return Seed_Stream{state = state}
}

seed_next_u32 :: proc(stream: ^Seed_Stream) -> u32 {
    stream.state = stream.state * 6364136223846793005 + 1442695040888963407
    return u32(stream.state >> 32)
}

seed_next_unit :: proc(stream: ^Seed_Stream) -> f32 {
    return f32(seed_next_u32(stream)) / 4294967295.0
}

seed_pick_index :: proc(stream: ^Seed_Stream, count: int) -> int {
    if count <= 0 {
        return 0
    }
    return int(seed_next_u32(stream) % u32(count))
}

