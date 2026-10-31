package main

import "core:os"
import "core:fmt"

read_game_file :: proc(path: string, allocator := context.allocator) -> ([]u8, bool) {
    data, err := os.read_entire_file(path, allocator)
    return data, err == nil
}

write_game_file :: proc(path: string, data: []u8) -> bool {
    err := os.write_entire_file(path, data)
    if err != nil { fmt.eprintf("[file] cannot write %s: %v\n", path, err) }
    return err == nil
}
