package main

import "core:os"
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
