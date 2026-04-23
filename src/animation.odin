package main

import "core:encoding/json"
import "core:math"
import "core:os"
import "core:strings"
import rl  "vendor:raylib"
import cw  "clockwork"

@(private = "file")
json_f32 :: proc(v: json.Value) -> f32 {
    switch n in v {
    case json.Float:   return f32(n)
    case json.Integer: return f32(n)
    case json.Null, bool, string, json.Array, json.Object:
    }
    return 0
}

ANIM_STATE_COUNT :: len(cw.AnimStateName)

AnimClipDef :: struct {
    start_frame: int,
    frame_count: int,
    fps:         f32,
    looping:     bool,
}

AnimSheetDef :: struct {
    frame_width:  int,
    frame_height: int,
    columns:      int,
    clips:        [ANIM_STATE_COUNT]AnimClipDef,
    has_clip:     [ANIM_STATE_COUNT]bool,
}

@(private = "file")
g_anim_def_cache: map[string]Maybe(AnimSheetDef)

init_anim_cache :: proc() {
    g_anim_def_cache = make(map[string]Maybe(AnimSheetDef))
}

shutdown_anim_cache :: proc() {
    for k in g_anim_def_cache {
        delete(k)
    }
    delete(g_anim_def_cache)
}

@(private = "file")
ANIM_STATE_NAMES := [ANIM_STATE_COUNT]string{ "idle", "walk", "dodge", "attack", "death" }

get_or_load_anim_def :: proc(stem: string) -> (def: AnimSheetDef, ok: bool) {
    if cached, found := g_anim_def_cache[stem]; found {
        if d, has := cached.?; has {
            return d, true
        }
        return {}, false
    }

    path_buf: [256]u8
    n := copy(path_buf[:], "data/sprites/entities/")
    n += copy(path_buf[n:], stem)
    n += copy(path_buf[n:], ".json")
    path_buf[n] = 0

    raw, read_ok := os.read_entire_file(string(path_buf[:n]), context.temp_allocator)
    if !read_ok || len(raw) == 0 {
        owned := strings.clone(stem)
        g_anim_def_cache[owned] = nil
        return {}, false
    }

    parsed, parse_err := json.parse(raw, allocator = context.temp_allocator)
    if parse_err != .None {
        owned := strings.clone(stem)
        g_anim_def_cache[owned] = nil
        return {}, false
    }

    root, root_ok := parsed.(json.Object)
    if !root_ok {
        owned := strings.clone(stem)
        g_anim_def_cache[owned] = nil
        return {}, false
    }

    result: AnimSheetDef
    if v, vok := root["frame_width"];  vok { result.frame_width  = int(json_f32(v)) }
    if v, vok := root["frame_height"]; vok { result.frame_height = int(json_f32(v)) }
    if v, vok := root["columns"];      vok { result.columns      = int(json_f32(v)) }

    if result.frame_width <= 0 || result.frame_height <= 0 || result.columns <= 0 {
        owned := strings.clone(stem)
        g_anim_def_cache[owned] = nil
        return {}, false
    }

    if states_obj, sok := root["states"].(json.Object); sok {
        for si in cw.AnimStateName {
            name := ANIM_STATE_NAMES[si]
            clip_val, clip_ok := states_obj[name]
            if !clip_ok { continue }
            clip_obj, cobj_ok := clip_val.(json.Object)
            if !cobj_ok { continue }

            clip: AnimClipDef
            if v, vok := clip_obj["start_frame"]; vok { clip.start_frame = int(json_f32(v)) }
            if v, vok := clip_obj["frame_count"]; vok { clip.frame_count = int(json_f32(v)) }
            if v, vok := clip_obj["fps"];         vok { clip.fps         = json_f32(v) }
            if v, vok := clip_obj["looping"];     vok {
                if b, bok := v.(bool); bok { clip.looping = b }
            }
            if clip.frame_count <= 0 { clip.frame_count = 1 }
            if clip.fps <= 0         { clip.fps = 6 }

            result.clips[si]    = clip
            result.has_clip[si] = true
        }
    }

    owned := strings.clone(stem)
    g_anim_def_cache[owned] = result
    return result, true
}

ANIM_WALK_SPEED_THRESH :: f32(8.0)

animation_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    ids := cw.world_query(w, cw.query_mask(.AnimState, .Transform))
    defer delete(ids)

    for id in ids {
        anim := cw.world_get_anim_state(w, id)

        desired := cw.AnimStateName.Idle

        if cw.world_has_component(w, id, .Respawn) &&
           cw.world_get_respawn(w, id).timer > 0 {
            desired = .Death
        } else if cw.world_has_component(w, id, .DodgeState) &&
                  cw.world_get_dodge(w, id).active {
            desired = .Dodge
        } else if cw.world_has_component(w, id, .Velocity) {
            vel := cw.world_get_velocity(w, id).value
            speed := math.sqrt(vel[0]*vel[0] + vel[1]*vel[1])
            if speed > ANIM_WALK_SPEED_THRESH {
                desired = .Walk
            }
        }

        if desired != anim.current_state {
            anim.current_state = desired
            anim.frame_index   = 0
            anim.elapsed       = 0
        }

        sprite_stem := get_entity_sprite_stem(w, id)
        adef, has_def := get_or_load_anim_def(sprite_stem)
        if !has_def { continue }

        state := anim.current_state
        if !adef.has_clip[state] {
            if adef.has_clip[cw.AnimStateName.Idle] { state = .Idle } else { continue }
        }

        clip := adef.clips[state]

        anim.elapsed += dt
        frame_dur := f32(1.0) / clip.fps
        for anim.elapsed >= frame_dur {
            anim.elapsed -= frame_dur
            anim.frame_index += 1
            if anim.frame_index >= clip.frame_count {
                if clip.looping {
                    anim.frame_index = 0
                } else {
                    anim.frame_index = clip.frame_count - 1
                    anim.elapsed = 0
                    break
                }
            }
        }
    }
}

@(private = "file")
PLAYER_STEM  :: "player_wanderer"
@(private = "file")
ENEMY_STEM   :: "enemy_melee"
@(private = "file")
NPC_STEM     :: "npc_shopkeeper"
@(private = "file")
WORKBENCH_STEM :: "mutation_workbench"

get_entity_sprite_stem :: proc(w: ^cw.World, id: int) -> string {
    if cw.world_has_component(w, id, .RenderConfig) {
        rc := cw.world_get_render_config(w, id)
        if rc.sprite_len > 0 {
            return string(rc.sprite_name[:rc.sprite_len])
        }
    }

    for slot in 0..<cw.MAX_PLAYERS {
        if id == w.player_ids[slot] { return PLAYER_STEM }
    }
    if cw.world_has_component(w, id, .AIAgent) {
        ai := cw.world_get_ai(w, id)
        if ai.ai_type == .Ranged { return "enemy_ranged" }
        return ENEMY_STEM
    }
    if cw.world_has_component(w, id, .NPC) {
        if cw.world_get_npc(w, id).npc_type == .MutationWorkbench {
            return WORKBENCH_STEM
        }
        return NPC_STEM
    }
    return ENEMY_STEM
}

anim_source_rect :: proc(w: ^cw.World, id: int, full_src: rl.Rectangle, sprite_stem: string) -> rl.Rectangle {
    if !cw.world_has_component(w, id, .AnimState) {
        return full_src
    }

    adef, has_def := get_or_load_anim_def(sprite_stem)
    if !has_def {
        return full_src
    }

    anim := cw.world_get_anim_state(w, id)
    state := anim.current_state
    if !adef.has_clip[state] {
        if adef.has_clip[cw.AnimStateName.Idle] { state = .Idle } else { return full_src }
    }

    clip := adef.clips[state]
    abs_frame := clip.start_frame + anim.frame_index
    col := abs_frame %% adef.columns
    row := abs_frame /  adef.columns

    return rl.Rectangle{
        f32(col * adef.frame_width),
        f32(row * adef.frame_height),
        f32(adef.frame_width),
        f32(adef.frame_height),
    }
}
