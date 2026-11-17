package main

import "core:os"
import "core:math/rand"
import "core:fmt"

read_game_file :: proc(path: string, allocator := context.allocator) -> ([]u8, bool) {
    data, err := os.read_entire_file(path, allocator)
    return data, err == nil
}

write_game_file :: proc(path: string, data: []u8) -> bool {
    tmp := fmt.tprintf("%s.tmp", path)
    err := os.write_entire_file(tmp, data)
    if err != nil {
        fmt.eprintf("[file] cannot write %s: %v\n", tmp, err)
        return false
    }
    if rerr := os.rename(tmp, path); rerr != nil {
        fmt.eprintf("[file] cannot replace %s: %v\n", path, rerr)
        return false
    }
    return true
}

// P1a step 4: raylib used to provide these, and package main no longer imports it.

// True if a file exists at `path`.
file_exists :: proc(path: cstring) -> bool {
    return os.exists(string(path))
}

// Uniform random integer in [lo, hi], matching raylib's GetRandomValue range (both ends included).
random_int :: proc(lo, hi: i32) -> i32 {
    if hi <= lo { return lo }
    return lo + rand.int31_max(hi - lo + 1)
}
