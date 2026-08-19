package main

import "core:encoding/json"
import "core:os"


MAX_LORE_PAGES    :: 128
MAX_RECORDINGS    :: 64
LORE_BODY_LEN     :: 1024
RECORDING_LEN     :: 256

LorePage :: struct {
    id:      u8,
    title:   [80]u8,
    body:    [LORE_BODY_LEN]u8,
}


Recording :: struct {
    id:         u8,
    title:      [80]u8,
    transcript: [RECORDING_LEN]u8,
    sfx_key:    [48]u8,
    duration:   f32,
}

g_lore_db:      [MAX_LORE_PAGES]LorePage
g_lore_count:   int
g_recording_db: [MAX_RECORDINGS]Recording
g_recording_count: int


@(private = "file")
lore_jf32 :: proc(v: json.Value) -> f32 {
    switch n in v {
    case json.Float:   return f32(n)
    case json.Integer: return f32(n)
    case json.Null, bool, string, json.Array, json.Object:
    }
    return 0
}

@(private = "file")
str_to_fixed :: proc(dst: []u8, src: string) {
    n := min(len(src), len(dst) - 1)
    copy(dst[:n], src[:n])
    dst[n] = 0
}

lore_db_load :: proc() {
    lore_load_pages("data/lore.json")
    lore_load_recordings("data/recordings.json")
}

@(private = "file")
lore_load_pages :: proc(path: string) {
    data, ok := os.read_entire_file(path)
    if !ok { return }
    defer delete(data)

    val, err := json.parse(data)
    if err != .None { return }
    defer json.destroy_value(val)

    arr, is_arr := val.(json.Array)
    if !is_arr { return }

    for elem in arr {
        if g_lore_count >= MAX_LORE_PAGES { break }
        obj, is_obj := elem.(json.Object)
        if !is_obj { continue }

        p := &g_lore_db[g_lore_count]
        if id_v, has := obj["id"]; has {
            p.id = u8(lore_jf32(id_v))
        }
        if t_v, has := obj["title"]; has {
            if s, is_s := t_v.(json.String); is_s {
                str_to_fixed(p.title[:], string(s))
            }
        }
        if b_v, has := obj["body"]; has {
            if s, is_s := b_v.(json.String); is_s {
                str_to_fixed(p.body[:], string(s))
            }
        }
        g_lore_count += 1
    }
}

@(private = "file")
lore_load_recordings :: proc(path: string) {
    data, ok := os.read_entire_file(path)
    if !ok { return }
    defer delete(data)

    val, err := json.parse(data)
    if err != .None { return }
    defer json.destroy_value(val)

    arr, is_arr := val.(json.Array)
    if !is_arr { return }

    for elem in arr {
        if g_recording_count >= MAX_RECORDINGS { break }
        obj, is_obj := elem.(json.Object)
        if !is_obj { continue }

        r := &g_recording_db[g_recording_count]
        if id_v, has := obj["id"]; has {
            r.id = u8(lore_jf32(id_v))
        }
        if t_v, has := obj["title"]; has {
            if s, is_s := t_v.(json.String); is_s {
                str_to_fixed(r.title[:], string(s))
            }
        }
        if tr_v, has := obj["transcript"]; has {
            if s, is_s := tr_v.(json.String); is_s {
                str_to_fixed(r.transcript[:], string(s))
            }
        }
        if sfx_v, has := obj["sfx_key"]; has {
            if s, is_s := sfx_v.(json.String); is_s {
                str_to_fixed(r.sfx_key[:], string(s))
            }
        }
        if dur_v, has := obj["duration"]; has {
            r.duration = lore_jf32(dur_v)
        }
        g_recording_count += 1
    }
}


lore_get_page :: proc(id: u8) -> (^LorePage, bool) {
    for i in 0..<g_lore_count {
        if g_lore_db[i].id == id { return &g_lore_db[i], true }
    }
    return nil, false
}

lore_get_recording :: proc(id: u8) -> (^Recording, bool) {
    for i in 0..<g_recording_count {
        if g_recording_db[i].id == id { return &g_recording_db[i], true }
    }
    return nil, false
}


phonograph_tick :: proc(w: ^World, entity_id: int, dt: f32) {
    if !world_has_component(w, entity_id, .Phonograph) { return }
    ph := comp_get(w, entity_id, .Phonograph, PhonographComp)
    if !ph.is_playing { return }

    ph.play_timer -= dt
    if ph.play_timer <= 0 {
        ph.is_playing  = false
        ph.play_timer  = 0

    }
}
