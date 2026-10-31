package main

import "core:fmt"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

ANIM_ED_KEY_CAP    :: 64
ANIM_ED_FIELD_CAP  :: 20
ANIM_ED_PANEL_W    :: 179
ANIM_ED_PREV_W     :: 140
ANIM_ED_BOT_H      :: 35
ANIM_ED_HDR_H      :: 24
ANIM_ED_PICKER_MAX :: 8

ANIM_ED_BG        :: rl.Color{  15,  12,  10, 248 }
ANIM_ED_PANEL_BG  :: rl.Color{  22,  18,  14, 255 }
ANIM_ED_BORDER    :: rl.Color{  55,  46,  34, 255 }
ANIM_ED_ACCENT    :: rl.Color{ 190, 140,  58, 255 }
ANIM_ED_TEXT      :: rl.Color{ 215, 205, 185, 255 }
ANIM_ED_MUTED     :: rl.Color{ 120, 110,  95, 255 }
ANIM_ED_HOVER_BG  :: rl.Color{  46,  38,  28, 255 }
ANIM_ED_ACTIVE_BG :: rl.Color{  64,  50,  26, 255 }
ANIM_ED_INPUT_BG  :: rl.Color{  26,  22,  18, 255 }
ANIM_ED_FOCUS_BDR :: rl.Color{ 190, 140,  58, 220 }
ANIM_ED_DIRTY_COL :: rl.Color{ 220, 100,  40, 255 }
ANIM_ED_OK_COL    :: rl.Color{ 100, 200, 100, 255 }
ANIM_ED_CLIP_COL  :: rl.Color{ 190, 140,  58, 110 }
ANIM_ED_START_COL :: rl.Color{ 100, 200, 100, 200 }

AnimEdField :: enum {
    None,
    Key,
    FrameWidth, FrameHeight, Columns,
    StartFrame, FrameCount, FPS,
    AnchorX, AnchorY,
    ProjectileX, ProjectileY,
    CollisionX, CollisionY, CollisionW, CollisionH,
}

AnimEditorState :: struct {
    open:            bool,

    key_buf:         [ANIM_ED_KEY_CAP]u8,
    key_len:         int,

    sprite_ok:       bool,
    sprite_tex:      rl.Texture2D,

    sheet:           AnimSheetDef,
    dirty:           bool,

    view_offset:     rl.Vector2,
    view_zoom:       f32,
    drag_last:       rl.Vector2,
    dragging:        bool,
    hover_frame:     int,

    active_state:    int,

    preview_playing: bool,
    preview_frame:   int,
    preview_elapsed: f32,

    found_keys:      [dynamic]string,
    picker_open:     bool,
    picker_scroll:   int,

    toast_msg:       [64]u8,
    toast_len:       int,
    toast_timer:     f32,

    focused_field:   AnimEdField,
    field_buf:       [ANIM_ED_FIELD_CAP]u8,
    field_len:       int,
    bs_timer:        f32,
}

g_anim_ed: AnimEditorState

anim_editor_open :: proc() {
    if g_anim_ed.open { return }
    ed := &g_anim_ed
    ed.open          = true
    ed.view_zoom     = 2.0
    ed.hover_frame   = -1
    ed.focused_field = .Key
    if ed.found_keys == nil {
        ed.found_keys = make([dynamic]string)
    }
    anim_editor_scan_keys()
}

anim_editor_close :: proc() {
    if !g_anim_ed.open { return }
    ed := &g_anim_ed
    ed.open          = false
    ed.focused_field = .None
    ed.picker_open   = false
}

@(private = "file")
anim_editor_toast :: proc(msg: string) {
    ed  := &g_anim_ed
    n   := min(len(msg), len(ed.toast_msg)-1)
    copy(ed.toast_msg[:], msg[:n])
    ed.toast_len  = n
    ed.toast_timer = 2.5
}

@(private = "file")
anim_ed_key_stem :: proc() -> string {
    return string(g_anim_ed.key_buf[:g_anim_ed.key_len])
}

@(private = "file")
anim_ed_backspace :: proc() {
    ed := &g_anim_ed
    #partial switch ed.focused_field {
    case .None:
    case .Key:
        if ed.key_len > 0 {
            ed.key_len    -= 1
            ed.picker_open = ed.key_len > 0
        }
    case:
        if ed.field_len > 0 { ed.field_len -= 1 }
    }
}

@(private = "file")
anim_ed_handle_chars :: proc() {
    ed := &g_anim_ed
    for {
        ch := rl.GetCharPressed()
        if ch == 0 { break }
        switch ed.focused_field {
        case .None:
        case .Key:
            if ed.key_len < ANIM_ED_KEY_CAP - 1 {
                ed.key_buf[ed.key_len] = u8(ch)
                ed.key_len    += 1
                ed.picker_open = true
            }
        case .FrameWidth, .FrameHeight, .Columns, .StartFrame, .FrameCount, .AnchorX, .AnchorY, .ProjectileX, .ProjectileY, .CollisionX, .CollisionY, .CollisionW, .CollisionH:
            if ch >= '0' && ch <= '9' && ed.field_len < ANIM_ED_FIELD_CAP - 1 {
                ed.field_buf[ed.field_len] = u8(ch)
                ed.field_len += 1
            }
        case .FPS:
            has_dot := false
            for i in 0..<ed.field_len {
                if ed.field_buf[i] == '.' { has_dot = true; break }
            }
            ok_ch := (ch >= '0' && ch <= '9') || (ch == '.' && !has_dot)
            if ok_ch && ed.field_len < ANIM_ED_FIELD_CAP - 1 {
                ed.field_buf[ed.field_len] = u8(ch)
                ed.field_len += 1
            }
        }
    }
}

@(private = "file")
anim_ed_focus_field :: proc(id: AnimEdField) {
    ed := &g_anim_ed
    if ed.focused_field == id { return }
    anim_ed_commit_field()
    ed.focused_field = id
    ed.field_len     = 0

    switch id {
    case .None, .Key:
    case .FrameWidth:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.frame_width))
        ed.field_buf[ed.field_len] = 0
    case .FrameHeight:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.frame_height))
        ed.field_buf[ed.field_len] = 0
    case .Columns:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.columns))
        ed.field_buf[ed.field_len] = 0
    case .StartFrame:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.clips[ed.active_state].start_frame))
        ed.field_buf[ed.field_len] = 0
    case .FrameCount:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.clips[ed.active_state].frame_count))
        ed.field_buf[ed.field_len] = 0
    case .FPS:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%.1f", ed.sheet.clips[ed.active_state].fps))
        ed.field_buf[ed.field_len] = 0
    case .AnchorX:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.anchor_px_x))
        ed.field_buf[ed.field_len] = 0
    case .AnchorY:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.anchor_px_y))
        ed.field_buf[ed.field_len] = 0
    case .ProjectileX:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.clips[ed.active_state].muzzle_px_x))
        ed.field_buf[ed.field_len] = 0
    case .ProjectileY:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.clips[ed.active_state].muzzle_px_y))
        ed.field_buf[ed.field_len] = 0
    case .CollisionX:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.collision_px_x))
        ed.field_buf[ed.field_len] = 0
    case .CollisionY:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.collision_px_y))
        ed.field_buf[ed.field_len] = 0
    case .CollisionW:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.collision_px_w))
        ed.field_buf[ed.field_len] = 0
    case .CollisionH:
        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ed.sheet.collision_px_h))
        ed.field_buf[ed.field_len] = 0
    }
}

@(private = "file")
anim_ed_commit_field :: proc() {
    ed := &g_anim_ed
    if ed.focused_field == .None || ed.focused_field == .Key { return }
    if ed.field_len == 0 { return }
    val := string(ed.field_buf[:ed.field_len])
    switch ed.focused_field {
    case .None, .Key:
    case .FrameWidth:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            if ed.sheet.frame_width != v { ed.sheet.frame_width = v; ed.dirty = true }
        }
    case .FrameHeight:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            if ed.sheet.frame_height != v { ed.sheet.frame_height = v; ed.dirty = true }
        }
    case .Columns:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            if ed.sheet.columns != v { ed.sheet.columns = v; ed.dirty = true }
        }
    case .StartFrame:
        if v, ok := strconv.parse_int(val); ok && v >= 0 {
            if ed.sheet.clips[ed.active_state].start_frame != v {
                ed.sheet.clips[ed.active_state].start_frame = v
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true; ed.preview_frame = 0
            }
        }
    case .FrameCount:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            if ed.sheet.clips[ed.active_state].frame_count != v {
                ed.sheet.clips[ed.active_state].frame_count = v
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true; ed.preview_frame = 0
            }
        }
    case .FPS:
        if v, ok := strconv.parse_f32(val); ok && v > 0 {
            if ed.sheet.clips[ed.active_state].fps != v {
                ed.sheet.clips[ed.active_state].fps = v
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true
            }
        }
    case .AnchorX:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_width, 1))
            if ed.sheet.anchor_px_x != v { ed.sheet.anchor_px_x = v; ed.dirty = true }
        }
    case .AnchorY:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_height, 1))
            if ed.sheet.anchor_px_y != v { ed.sheet.anchor_px_y = v; ed.dirty = true }
        }
    case .ProjectileX:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_width, 1))
            if ed.sheet.clips[ed.active_state].muzzle_px_x != v {
                ed.sheet.clips[ed.active_state].muzzle_px_x = v
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true
            }
        }
    case .ProjectileY:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_height, 1))
            if ed.sheet.clips[ed.active_state].muzzle_px_y != v {
                ed.sheet.clips[ed.active_state].muzzle_px_y = v
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true
            }
        }
    case .CollisionX:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_width, 1))
            if ed.sheet.collision_px_x != v { ed.sheet.collision_px_x = v; ed.sheet.has_collision = true; ed.dirty = true }
        }
    case .CollisionY:
        if v, ok := strconv.parse_int(val); ok {
            v = clamp(v, 0, max(ed.sheet.frame_height, 1))
            if ed.sheet.collision_px_y != v { ed.sheet.collision_px_y = v; ed.sheet.has_collision = true; ed.dirty = true }
        }
    case .CollisionW:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            v = clamp(v, 1, max(ed.sheet.frame_width - ed.sheet.collision_px_x, 1))
            if ed.sheet.collision_px_w != v { ed.sheet.collision_px_w = v; ed.sheet.has_collision = true; ed.dirty = true }
        }
    case .CollisionH:
        if v, ok := strconv.parse_int(val); ok && v > 0 {
            v = clamp(v, 1, max(ed.sheet.frame_height - ed.sheet.collision_px_y, 1))
            if ed.sheet.collision_px_h != v { ed.sheet.collision_px_h = v; ed.sheet.has_collision = true; ed.dirty = true }
        }
    }
}

@(private = "file")
anim_editor_load :: proc(stem: string) {
    ed := &g_anim_ed
    if len(stem) == 0 { return }
    ed.sprite_ok = false
    ed.dirty     = false

    tex, _, tok := get_entity_sprite_tex(stem)
    if !tok {
        anim_editor_toast("Texture not found!")
        return
    }
    ed.sprite_tex = tex
    ed.sprite_ok  = true

    anim_def_cache_evict(stem)
    def, def_ok := get_or_load_anim_def(stem)
    if def_ok {
        ed.sheet = def
        anim_editor_toast("Loaded OK")
    } else {
        tw := int(tex.width)
        th := int(tex.height)
        ed.sheet = AnimSheetDef{
            frame_width  = tw,
            frame_height = th,
            columns      = 1,
            anchor_px_x  = tw / 2,
            anchor_px_y  = th,
        }
        ed.sheet.clips[0]    = AnimClipDef{ start_frame = 0, frame_count = 1, fps = 6, looping = true }
        ed.sheet.has_clip[0] = true
        ed.dirty = true
        anim_editor_toast("No JSON - created defaults")
    }

    ed.view_offset   = { f32(tex.width) * 0.5, f32(tex.height) * 0.5 }
    ed.view_zoom     = max(2.0, uis(240) / f32(max(tex.width, 1)))
    ed.preview_frame   = 0
    ed.preview_elapsed = 0
    ed.picker_open     = false
}

@(private = "file")
anim_editor_save :: proc() {
    ed   := &g_anim_ed
    if !ed.sprite_ok { return }
    stem := anim_ed_key_stem()
    if stem == "" { return }

    sb: strings.Builder
    strings.builder_init(&sb, context.temp_allocator)

    tmp: [256]u8

    strings.write_string(&sb, "{\n")
    strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "  \"frame_width\": %d,\n",  ed.sheet.frame_width))])
    strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "  \"frame_height\": %d,\n", ed.sheet.frame_height))])
    strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "  \"columns\": %d,\n",      ed.sheet.columns))])
    strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "  \"anchor\": [%d, %d],\n", ed.sheet.anchor_px_x, ed.sheet.anchor_px_y))])
    if ed.sheet.has_collision {
        strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "  \"collision\": [%d, %d, %d, %d],\n",
            ed.sheet.collision_px_x, ed.sheet.collision_px_y, ed.sheet.collision_px_w, ed.sheet.collision_px_h))])
    }
    strings.write_string(&sb, "  \"states\": {\n")

    first := true
    for si in 0..<ANIM_STATE_COUNT {
        if !ed.sheet.has_clip[si] { continue }
        if !first { strings.write_string(&sb, ",\n") }
        first = false
        clip   := ed.sheet.clips[si]
        loop_s := "false"; if clip.looping { loop_s = "true" }

        strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], "    \"%s\": ", ANIM_STATE_NAMES[si]))])
        strings.write_string(&sb, "{ ")
        strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:],
            "\"start_frame\": %d, \"frame_count\": %d, \"fps\": %.1f, \"looping\": %s",
            clip.start_frame, clip.frame_count, clip.fps, loop_s))])
        if clip.muzzle_px_x != 0 || clip.muzzle_px_y != 0 {
            strings.write_bytes(&sb, tmp[:len(fmt.bprintf(tmp[:], ", \"muzzle\": [%d, %d]", clip.muzzle_px_x, clip.muzzle_px_y))])
        }
        strings.write_string(&sb, " }")
    }
    strings.write_string(&sb, "\n  }\n}\n")

    data := transmute([]u8)strings.to_string(sb)

    path_buf: [256]u8
    pn := len(fmt.bprintf(path_buf[:], "data/sprites/entities/%s.json", stem))

    if write_game_file(string(path_buf[:pn]), data) {
        anim_def_cache_evict(stem)
        ed.dirty = false
        anim_editor_toast("Saved!")
    } else {
        anim_editor_toast("Save FAILED!")
    }
}

@(private = "file")
anim_editor_revert :: proc() {
    if !g_anim_ed.sprite_ok { return }
    stem := anim_ed_key_stem()
    anim_editor_load(stem)
    anim_editor_toast("Reverted")
}

@(private = "file")
anim_editor_scan_keys :: proc() {
    ed := &g_anim_ed
    for k in ed.found_keys { delete(k) }
    clear(&ed.found_keys)

    seen := make(map[string]bool, context.temp_allocator)

    png_matches, _ := filepath.glob("data/sprites/entities/*.png", context.temp_allocator)
    for m in png_matches {
        base := filepath.base(m)
        if strings.has_suffix(base, ".png") {
            stem := base[:len(base)-4]
            if !(stem in seen) {
                seen[stem] = true
                append(&ed.found_keys, strings.clone(stem))
            }
        }
    }

    json_matches, _ := filepath.glob("data/sprites/entities/*.json", context.temp_allocator)
    for m in json_matches {
        base := filepath.base(m)
        if strings.has_suffix(base, ".json") {
            stem := base[:len(base)-5]
            if !(stem in seen) {
                seen[stem] = true
                append(&ed.found_keys, strings.clone(stem))
            }
        }
    }
}

update_anim_editor :: proc(dt: f32) {
    if !g_anim_ed.open { return }
    ed := &g_anim_ed

    if rl.IsKeyPressed(.F3) { anim_editor_close(); return }

    if ed.toast_timer > 0 { ed.toast_timer -= dt }

    if ed.preview_playing && ed.sprite_ok && ed.sheet.has_clip[ed.active_state] {
        clip := ed.sheet.clips[ed.active_state]
        fps  := max(clip.fps, 1)
        ed.preview_elapsed += dt
        frame_dur := f32(1.0) / fps
        for ed.preview_elapsed >= frame_dur {
            ed.preview_elapsed -= frame_dur
            ed.preview_frame   += 1
            if ed.preview_frame >= clip.frame_count {
                if clip.looping {
                    ed.preview_frame = 0
                } else {
                    ed.preview_frame   = clip.frame_count - 1
                    ed.preview_elapsed = 0
                    break
                }
            }
        }
    }

    if rl.IsKeyPressed(.ESCAPE) {
        if ed.focused_field != .None && ed.focused_field != .Key {
            anim_ed_commit_field(); ed.focused_field = .None
        } else if ed.picker_open {
            ed.picker_open = false
        } else {
            anim_editor_close()
        }
        return
    }

    if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
        #partial switch ed.focused_field {
        case .Key:
            anim_editor_load(anim_ed_key_stem())
        case .None:
        case:
            anim_ed_commit_field(); ed.focused_field = .None
        }
        return
    }

    if ed.focused_field != .None { anim_ed_handle_chars() }

    if ed.focused_field != .None {
        if rl.IsKeyPressed(.BACKSPACE) {
            anim_ed_backspace(); ed.bs_timer = 0.35
        } else if rl.IsKeyDown(.BACKSPACE) {
            ed.bs_timer -= dt
            if ed.bs_timer <= 0 { ed.bs_timer = 0.05; anim_ed_backspace() }
        } else {
            ed.bs_timer = 0
        }
    }

    if rl.IsKeyPressed(.TAB) {
        switch ed.focused_field {
        case .StartFrame:  anim_ed_focus_field(.FrameCount)
        case .FrameCount:  anim_ed_focus_field(.FPS)
        case .FPS:         anim_ed_focus_field(.StartFrame)
        case .FrameWidth:  anim_ed_focus_field(.FrameHeight)
        case .FrameHeight: anim_ed_focus_field(.Columns)
        case .Columns:     anim_ed_focus_field(.FrameWidth)
        case .AnchorX:     anim_ed_focus_field(.AnchorY)
        case .AnchorY:     anim_ed_focus_field(.AnchorX)
        case .ProjectileX: anim_ed_focus_field(.ProjectileY)
        case .ProjectileY: anim_ed_focus_field(.ProjectileX)
        case .CollisionX:   anim_ed_focus_field(.CollisionY)
        case .CollisionY:   anim_ed_focus_field(.CollisionW)
        case .CollisionW:   anim_ed_focus_field(.CollisionH)
        case .CollisionH:   anim_ed_focus_field(.CollisionX)
        case .None, .Key:
        }
    }

    ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    if ctrl && rl.IsKeyPressed(.S) {
        anim_ed_commit_field()
        anim_editor_save()
    }
}

@(private = "file")
anim_ed_btn :: proc(rect: rl.Rectangle, label: cstring, mp: rl.Vector2) -> bool {
    hot     := rl.CheckCollisionPointRec(mp, rect)
    pressed := hot && rl.IsMouseButtonReleased(.LEFT)
    bg  := ANIM_ED_INPUT_BG; if hot { bg = ANIM_ED_HOVER_BG }
    rl.DrawRectangleRounded(rect, 0.25, 6, bg)
    rl.DrawRectangleRoundedLinesEx(rect, 0.25, 6, 1, ANIM_ED_BORDER)
    fs  := uis(10)
    tsz := rl.MeasureTextEx(g_font, label, fs, 0.5)
    col := ANIM_ED_ACCENT; if !hot { col = ANIM_ED_TEXT }
    rl.DrawTextEx(g_font, label,
        { rect.x + (rect.width - tsz.x)*0.5, rect.y + (rect.height - tsz.y)*0.5 },
        fs, 0.5, col)
    return pressed
}

@(private = "file")
anim_ed_label :: proc(x, y: f32, text: cstring, fs: f32, col: rl.Color) {
    rl.DrawTextEx(g_font, text, {x, y}, fs, 0.5, col)
}

@(private = "file")
anim_ed_number_field :: proc(rect: rl.Rectangle, id: AnimEdField, mp: rl.Vector2) -> bool {
    ed      := &g_anim_ed
    hot     := rl.CheckCollisionPointRec(mp, rect)
    focused := ed.focused_field == id
    clicked := false

    if hot && rl.IsMouseButtonPressed(.LEFT) {
        anim_ed_focus_field(id)
        clicked = true
        focused = true
    }

    bg     := ANIM_ED_INPUT_BG
    if focused { bg = rl.Color{34, 28, 20, 255} } else if hot { bg = ANIM_ED_HOVER_BG }
    rl.DrawRectangleRec(rect, bg)
    border := ANIM_ED_BORDER; if focused { border = ANIM_ED_FOCUS_BDR }
    rl.DrawRectangleLinesEx(rect, 1, border)

    var_buf: [ANIM_ED_FIELD_CAP + 4]u8
    var_len: int
    if focused {
        var_len = min(ed.field_len, len(var_buf)-2)
        copy(var_buf[:], ed.field_buf[:var_len])
        if int(rl.GetTime() * 2) % 2 == 0 {
            var_buf[var_len] = '|'; var_len += 1
        }
    } else {
        switch id {
        case .FrameWidth:  var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.frame_width))
        case .FrameHeight: var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.frame_height))
        case .Columns:     var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.columns))
        case .StartFrame:  var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.clips[ed.active_state].start_frame))
        case .FrameCount:  var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.clips[ed.active_state].frame_count))
        case .FPS:         var_len = len(fmt.bprintf(var_buf[:], "%.1f", ed.sheet.clips[ed.active_state].fps))
        case .AnchorX:     var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.anchor_px_x))
        case .AnchorY:     var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.anchor_px_y))
        case .ProjectileX: var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.clips[ed.active_state].muzzle_px_x))
        case .ProjectileY: var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.clips[ed.active_state].muzzle_px_y))
        case .CollisionX:   var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.collision_px_x))
        case .CollisionY:   var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.collision_px_y))
        case .CollisionW:   var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.collision_px_w))
        case .CollisionH:   var_len = len(fmt.bprintf(var_buf[:], "%d",   ed.sheet.collision_px_h))
        case .None, .Key:
        }
    }
    var_buf[var_len] = 0

    fs  := uis(9)
    tsz := rl.MeasureTextEx(g_font, cstring(&var_buf[0]), fs, 0.5)
    tx  := rect.x + rect.width - tsz.x - uis(5)
    ty  := rect.y + (rect.height - tsz.y) * 0.5
    col := ANIM_ED_ACCENT; if !focused { col = ANIM_ED_TEXT }
    rl.DrawTextEx(g_font, cstring(&var_buf[0]), {tx, ty}, fs, 0.5, col)
    return clicked
}

@(private = "file")
anim_ed_draw_header :: proc(sw, hdr_y, hdr_h: f32, mp: rl.Vector2) {
    ed := &g_anim_ed
    rl.DrawRectangle(0, i32(hdr_y), i32(sw), i32(hdr_h), ANIM_ED_PANEL_BG)
    rl.DrawLine(0, i32(hdr_y + hdr_h - 1), i32(sw), i32(hdr_y + hdr_h - 1), ANIM_ED_BORDER)

    title_fs := uis(12)
    rl.DrawTextEx(g_font, "ANIMATION EDITOR", {uis(8), hdr_y + (hdr_h - title_fs)*0.5}, title_fs, 0.5, ANIM_ED_ACCENT)

    if ed.dirty {
        lbl := cstring("● unsaved changes")
        dsz := rl.MeasureTextEx(g_font, lbl, uis(9), 0.5)
        rl.DrawTextEx(g_font, lbl,
            {sw*0.5 - dsz.x*0.5, hdr_y + (hdr_h - dsz.y)*0.5},
            uis(9), 0.5, ANIM_ED_DIRTY_COL)
    }

    hint := cstring("[F3] Close   [Ctrl+S] Save   [Tab] Next field")
    hint_fs := uis(8)
    hsz  := rl.MeasureTextEx(g_font, hint, hint_fs, 0.5)
    rl.DrawTextEx(g_font, hint, {sw - hsz.x - uis(9), hdr_y + (hdr_h - hsz.y)*0.5}, hint_fs, 0.5, ANIM_ED_MUTED)
}

@(private = "file")
anim_ed_draw_left_panel :: proc(lp_x, lp_y, lp_w, lp_h: f32, mp: rl.Vector2) {
    ed  := &g_anim_ed
    fs  := uis(9)
    pad := uis(7)

    rl.DrawRectangle(i32(lp_x), i32(lp_y), i32(lp_w), i32(lp_h), ANIM_ED_PANEL_BG)
    rl.DrawLine(i32(lp_x + lp_w - 1), i32(lp_y), i32(lp_x + lp_w - 1), i32(lp_y + lp_h), ANIM_ED_BORDER)

    cy := lp_y + pad

    anim_ed_label(lp_x + pad, cy, "SPRITE KEY", uis(7), ANIM_ED_MUTED); cy += uis(12)

    key_h     := uis(17)
    key_rect  := rl.Rectangle{ lp_x + pad, cy, lp_w - pad*2, key_h }
    focus_key := ed.focused_field == .Key

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, key_rect) {
        if !focus_key { anim_ed_commit_field(); ed.focused_field = .Key }
    }

    key_bg := ANIM_ED_INPUT_BG; if focus_key { key_bg = rl.Color{34, 28, 20, 255} }
    rl.DrawRectangleRec(key_rect, key_bg)
    k_bdr := ANIM_ED_BORDER; if focus_key { k_bdr = ANIM_ED_FOCUS_BDR }
    rl.DrawRectangleLinesEx(key_rect, 1, k_bdr)

    disp: [ANIM_ED_KEY_CAP + 2]u8
    dn := ed.key_len
    copy(disp[:], ed.key_buf[:dn])
    if focus_key && int(rl.GetTime() * 2) % 2 == 0 { disp[dn] = '|'; dn += 1 }
    disp[dn] = 0
    k_col := ANIM_ED_TEXT; if focus_key { k_col = ANIM_ED_ACCENT }
    rl.DrawTextEx(g_font, cstring(&disp[0]),
        {key_rect.x + uis(4), key_rect.y + (key_rect.height - fs)*0.5}, fs, 0.5, k_col)

    if ed.key_len > 0 {
        s_col := ANIM_ED_MUTED; s_lbl := cstring("-")
        if ed.sprite_ok { s_col = ANIM_ED_OK_COL; s_lbl = cstring("OK") }
        tag_fs := uis(7)
        ssz := rl.MeasureTextEx(g_font, s_lbl, tag_fs, 0.5)
        rl.DrawTextEx(g_font, s_lbl,
            {key_rect.x + key_rect.width - ssz.x - uis(4), key_rect.y + (key_rect.height - ssz.y)*0.5},
            tag_fs, 0.5, s_col)
    }
    cy += key_h + uis(3)

    if ed.picker_open && ed.key_len > 0 {
        prefix := string(ed.key_buf[:ed.key_len])

        filtered: [64]string
        fc := 0
        for k in ed.found_keys {
            if strings.contains(k, prefix) && fc < 64 {
                filtered[fc] = k; fc += 1
            }
        }

        if fc > 0 {
            ed.picker_scroll = clamp(ed.picker_scroll, 0, max(0, fc - ANIM_ED_PICKER_MAX))

            if rl.CheckCollisionPointRec(mp, rl.Rectangle{lp_x, lp_y, lp_w, lp_h}) {
                wh := rl.GetMouseWheelMove()
                if wh != 0 {
                    ed.picker_scroll = clamp(ed.picker_scroll - int(wh), 0, max(0, fc - ANIM_ED_PICKER_MAX))
                }
            }

            row_h   := uis(15)
            visible := min(fc - ed.picker_scroll, ANIM_ED_PICKER_MAX)
            ph      := f32(visible) * row_h + uis(2)
            pr      := rl.Rectangle{ lp_x + pad, cy, lp_w - pad*2, ph }
            rl.DrawRectangleRec(pr, ANIM_ED_INPUT_BG)
            rl.DrawRectangleLinesEx(pr, 1, ANIM_ED_BORDER)

            for row in 0..<visible {
                idx := ed.picker_scroll + row
                k   := filtered[idx]
                ir  := rl.Rectangle{ lp_x + pad, cy + f32(row)*row_h + uis(1), lp_w - pad*2, row_h - uis(1) }
                hot := rl.CheckCollisionPointRec(mp, ir)
                if hot { rl.DrawRectangleRec(ir, ANIM_ED_HOVER_BG) }
                kb: [ANIM_ED_KEY_CAP + 1]u8
                kn := copy(kb[:], k); kb[kn] = 0
                col := ANIM_ED_ACCENT; if !hot { col = ANIM_ED_TEXT }
                rl.DrawTextEx(g_font, cstring(&kb[0]),
                    {ir.x + uis(4), ir.y + (ir.height - fs)*0.5}, fs, 0.5, col)
                if hot && rl.IsMouseButtonReleased(.LEFT) {
                    ed.key_len = min(len(k), ANIM_ED_KEY_CAP - 1)
                    copy(ed.key_buf[:], k[:ed.key_len])
                    ed.picker_open = false
                    anim_editor_load(string(ed.key_buf[:ed.key_len]))
                }
            }
            cy += ph + pad
        } else {
            ed.picker_open = false
        }
    }

    rl.DrawLine(i32(lp_x + pad), i32(cy), i32(lp_x + lp_w - pad), i32(cy), ANIM_ED_BORDER)
    cy += pad

    if !ed.sprite_ok {
        anim_ed_label(lp_x + pad, cy, "Press Enter to load", uis(8), ANIM_ED_MUTED)
        return
    }

    anim_ed_label(lp_x + pad, cy, "STATE", uis(7), ANIM_ED_MUTED); cy += uis(12)

    state_shorts := [ANIM_STATE_COUNT]cstring{ "Idle", "Walk", "Dodg", "Atk", "Die", "Hit" }
    tab_w := (lp_w - pad*2) / f32(ANIM_STATE_COUNT)
    tab_h := uis(17)
    tab_fs := uis(8)
    for si in 0..<ANIM_STATE_COUNT {
        tr     := rl.Rectangle{ lp_x + pad + f32(si)*tab_w, cy, tab_w - uis(2), tab_h }
        hot_t  := rl.CheckCollisionPointRec(mp, tr)
        active := ed.active_state == si

        t_bg := ANIM_ED_INPUT_BG
        if active  { t_bg = ANIM_ED_ACTIVE_BG } else if hot_t { t_bg = ANIM_ED_HOVER_BG }
        rl.DrawRectangleRec(tr, t_bg)
        if active { rl.DrawRectangleLinesEx(tr, 1, ANIM_ED_ACCENT) }

        t_col := ANIM_ED_MUTED
        if active                      { t_col = ANIM_ED_ACCENT }
        else if ed.sheet.has_clip[si]  { t_col = ANIM_ED_TEXT   }
        tsz := rl.MeasureTextEx(g_font, state_shorts[si], tab_fs, 0.5)
        rl.DrawTextEx(g_font, state_shorts[si],
            {tr.x + (tr.width - tsz.x)*0.5, tr.y + (tr.height - tsz.y)*0.5},
            tab_fs, 0.5, t_col)

        if hot_t && rl.IsMouseButtonReleased(.LEFT) && !active {
            anim_ed_commit_field()
            if ed.focused_field != .None && ed.focused_field != .Key { ed.focused_field = .None }
            ed.active_state    = si
            ed.preview_frame   = 0
            ed.preview_elapsed = 0
        }
    }
    cy += tab_h + pad

    anim_ed_label(lp_x + pad, cy, "CLIP", uis(7), ANIM_ED_MUTED); cy += uis(11)

    {
        cb_sz := uis(12)
        cx_r  := rl.Rectangle{ lp_x + pad, cy, cb_sz, cb_sz }
        hot_c := rl.CheckCollisionPointRec(mp, cx_r)
        rl.DrawRectangleRec(cx_r, ANIM_ED_INPUT_BG)
        b_col := ANIM_ED_BORDER; if hot_c { b_col = ANIM_ED_ACCENT }
        rl.DrawRectangleLinesEx(cx_r, 1, b_col)
        if ed.sheet.has_clip[ed.active_state] {
            rl.DrawLine(i32(cx_r.x + cb_sz*0.18), i32(cx_r.y + cb_sz*0.50),
                        i32(cx_r.x + cb_sz*0.42), i32(cx_r.y + cb_sz*0.78), ANIM_ED_ACCENT)
            rl.DrawLine(i32(cx_r.x + cb_sz*0.42), i32(cx_r.y + cb_sz*0.78),
                        i32(cx_r.x + cb_sz*0.85), i32(cx_r.y + cb_sz*0.22), ANIM_ED_ACCENT)
        }
        if hot_c && rl.IsMouseButtonReleased(.LEFT) {
            ed.sheet.has_clip[ed.active_state] = !ed.sheet.has_clip[ed.active_state]
            ed.dirty = true
        }
        anim_ed_label(lp_x + pad + cb_sz + uis(4), cy + (cb_sz - fs)*0.5, "Enabled", fs, ANIM_ED_TEXT)
        cy += uis(16)
    }

    label_w := uis(55)
    fh      := uis(16)
    fgap    := uis(3)
    fx      := lp_x + pad + label_w
    fw      := lp_w - pad*2 - label_w

    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "Start frame", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, fw, fh}, .StartFrame, mp)
    cy += fh + fgap

    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "Frame count", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, fw, fh}, .FrameCount, mp)
    cy += fh + fgap

    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "FPS", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, fw, fh}, .FPS, mp)
    cy += fh + fgap

    {
        cb_sz := uis(12)
        cx_r  := rl.Rectangle{ fx, cy, cb_sz, cb_sz }
        hot_c := rl.CheckCollisionPointRec(mp, cx_r)
        rl.DrawRectangleRec(cx_r, ANIM_ED_INPUT_BG)
        b_col := ANIM_ED_BORDER; if hot_c { b_col = ANIM_ED_ACCENT }
        rl.DrawRectangleLinesEx(cx_r, 1, b_col)
        if ed.sheet.clips[ed.active_state].looping {
            rl.DrawLine(i32(cx_r.x + cb_sz*0.18), i32(cx_r.y + cb_sz*0.50),
                        i32(cx_r.x + cb_sz*0.42), i32(cx_r.y + cb_sz*0.78), ANIM_ED_ACCENT)
            rl.DrawLine(i32(cx_r.x + cb_sz*0.42), i32(cx_r.y + cb_sz*0.78),
                        i32(cx_r.x + cb_sz*0.85), i32(cx_r.y + cb_sz*0.22), ANIM_ED_ACCENT)
        }
        if hot_c && rl.IsMouseButtonReleased(.LEFT) {
            ed.sheet.clips[ed.active_state].looping    = !ed.sheet.clips[ed.active_state].looping
            ed.sheet.has_clip[ed.active_state]         = true
            ed.dirty = true
        }
        anim_ed_label(lp_x + pad, cy + (cb_sz - fs)*0.5, "Looping", fs, ANIM_ED_MUTED)
        cy += uis(16)
    }

    rl.DrawLine(i32(lp_x + pad), i32(cy), i32(lp_x + lp_w - pad), i32(cy), ANIM_ED_BORDER)
    cy += uis(4)
    anim_ed_label(lp_x + pad, cy, "ANCHOR", uis(7), ANIM_ED_MUTED); cy += uis(11)

    half_fw := (fw - uis(3)) * 0.5
    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "X", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, half_fw, fh}, .AnchorX, mp)
    anim_ed_label(fx + half_fw + uis(3) + uis(2), cy + (fh-fs)*0.5, "Y", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx + half_fw + uis(3) + uis(9), cy, half_fw - uis(9), fh}, .AnchorY, mp)
    cy += fh + fgap

    anim_ed_label(lp_x + pad, cy, "PROJECTILE SPAWN", uis(7), ANIM_ED_MUTED); cy += uis(11)
    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "X", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, half_fw, fh}, .ProjectileX, mp)
    anim_ed_label(fx + half_fw + uis(3) + uis(2), cy + (fh-fs)*0.5, "Y", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx + half_fw + uis(3) + uis(9), cy, half_fw - uis(9), fh}, .ProjectileY, mp)
    cy += fh + fgap

    anim_ed_label(lp_x + pad, cy, "Ctrl-drag anchor  Shift-drag projectile", uis(7), ANIM_ED_MUTED)
    cy += uis(15)
    anim_ed_label(lp_x + pad, cy, "COLLISION BOX", uis(7), ANIM_ED_MUTED); cy += uis(11)
    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "X", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, half_fw, fh}, .CollisionX, mp)
    anim_ed_label(fx + half_fw + uis(3) + uis(2), cy + (fh-fs)*0.5, "Y", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx + half_fw + uis(3) + uis(9), cy, half_fw - uis(9), fh}, .CollisionY, mp)
    cy += fh + fgap
    anim_ed_label(lp_x + pad, cy + (fh-fs)*0.5, "W", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx, cy, half_fw, fh}, .CollisionW, mp)
    anim_ed_label(fx + half_fw + uis(3) + uis(2), cy + (fh-fs)*0.5, "H", fs, ANIM_ED_MUTED)
    anim_ed_number_field(rl.Rectangle{fx + half_fw + uis(3) + uis(9), cy, half_fw - uis(9), fh}, .CollisionH, mp)
}

@(private = "file")
anim_ed_draw_viewport :: proc(vp_x, vp_y, vp_w, vp_h: f32, mp: rl.Vector2) {
    ed   := &g_anim_ed
    over := rl.CheckCollisionPointRec(mp, rl.Rectangle{vp_x, vp_y, vp_w, vp_h})

    rl.DrawRectangle(i32(vp_x), i32(vp_y), i32(vp_w), i32(vp_h), rl.Color{18, 15, 12, 255})

    if !ed.sprite_ok {
        msg := cstring("Load a sprite to see the sheet")
        fs  := uis(10)
        sz  := rl.MeasureTextEx(g_font, msg, fs, 0.5)
        rl.DrawTextEx(g_font, msg,
            {vp_x + (vp_w - sz.x)*0.5, vp_y + (vp_h - sz.y)*0.5}, fs, 0.5, ANIM_ED_MUTED)
        rl.DrawRectangleLinesEx(rl.Rectangle{vp_x, vp_y, vp_w, vp_h}, 1, ANIM_ED_BORDER)
        return
    }

    tex  := ed.sprite_tex
    fw   := ed.sheet.frame_width
    fh   := ed.sheet.frame_height
    cols := ed.sheet.columns

    if over {
        if rl.IsMouseButtonPressed(.MIDDLE) || rl.IsMouseButtonPressed(.RIGHT) {
            ed.dragging  = true
            ed.drag_last = mp
        }
        ctrl_held := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
        shift_held := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
        if rl.IsMouseButtonDown(.LEFT) && ctrl_held && fw > 0 && fh > 0 {
            sx := ed.view_offset.x + (mp.x - vp_x - vp_w*0.5) / ed.view_zoom
            sy := ed.view_offset.y + (mp.y - vp_y - vp_h*0.5) / ed.view_zoom
            if sx >= 0 && sy >= 0 && sx < f32(tex.width) && sy < f32(tex.height) {
                lx := int(sx) %% fw
                ly := int(sy) %% fh
                nx := clamp(lx, 0, fw)
                ny := clamp(ly, 0, fh)
                if ed.sheet.anchor_px_x != nx || ed.sheet.anchor_px_y != ny {
                    ed.sheet.anchor_px_x = nx
                    ed.sheet.anchor_px_y = ny
                    ed.dirty = true
                    if ed.focused_field == .AnchorX {
                        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", nx))
                        ed.field_buf[ed.field_len] = 0
                    } else if ed.focused_field == .AnchorY {
                        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ny))
                        ed.field_buf[ed.field_len] = 0
                    }
                }
            }
        } else if rl.IsMouseButtonDown(.LEFT) && shift_held && fw > 0 && fh > 0 {
            sx := ed.view_offset.x + (mp.x - vp_x - vp_w*0.5) / ed.view_zoom
            sy := ed.view_offset.y + (mp.y - vp_y - vp_h*0.5) / ed.view_zoom
            if sx >= 0 && sy >= 0 && sx < f32(tex.width) && sy < f32(tex.height) {
                lx := int(sx) %% fw
                ly := int(sy) %% fh
                nx := clamp(lx, 0, fw)
                ny := clamp(ly, 0, fh)
                clip := &ed.sheet.clips[ed.active_state]
                if clip.muzzle_px_x != nx || clip.muzzle_px_y != ny {
                    clip.muzzle_px_x = nx
                    clip.muzzle_px_y = ny
                    ed.sheet.has_clip[ed.active_state] = true
                    ed.dirty = true
                    if ed.focused_field == .ProjectileX {
                        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", nx))
                        ed.field_buf[ed.field_len] = 0
                    } else if ed.focused_field == .ProjectileY {
                        ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", ny))
                        ed.field_buf[ed.field_len] = 0
                    }
                }
            }
        } else if rl.IsMouseButtonPressed(.LEFT) && fw > 0 && fh > 0 && cols > 0 && !ctrl_held && !shift_held {
            sx := ed.view_offset.x + (mp.x - vp_x - vp_w*0.5) / ed.view_zoom
            sy := ed.view_offset.y + (mp.y - vp_y - vp_h*0.5) / ed.view_zoom
            if sx >= 0 && sy >= 0 && sx < f32(tex.width) && sy < f32(tex.height) {
                abs_f := (int(sy) / fh) * cols + (int(sx) / fw)
                ed.sheet.clips[ed.active_state].start_frame = abs_f
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty        = true
                ed.preview_frame = 0
                if ed.focused_field == .StartFrame {
                    ed.field_len = len(fmt.bprintf(ed.field_buf[:], "%d", abs_f))
                    ed.field_buf[ed.field_len] = 0
                }
            }
        }
        wh := rl.GetMouseWheelMove()
        if wh != 0 {
            old_z := ed.view_zoom
            ed.view_zoom = clamp(ed.view_zoom * (1 + wh*0.15), 0.125, 64)
            lx := mp.x - vp_x - vp_w*0.5
            ly := mp.y - vp_y - vp_h*0.5
            ed.view_offset.x += lx/old_z - lx/ed.view_zoom
            ed.view_offset.y += ly/old_z - ly/ed.view_zoom
        }
    }

    if ed.dragging {
        if rl.IsMouseButtonDown(.MIDDLE) || rl.IsMouseButtonDown(.RIGHT) {
            ed.view_offset.x -= (mp.x - ed.drag_last.x) / ed.view_zoom
            ed.view_offset.y -= (mp.y - ed.drag_last.y) / ed.view_zoom
            ed.drag_last = mp
        } else {
            ed.dragging = false
        }
    }

    tw := f32(tex.width); th := f32(tex.height)
    ed.view_offset.x = clamp(ed.view_offset.x, -tw, tw*2)
    ed.view_offset.y = clamp(ed.view_offset.y, -th, th*2)

    tex_x := vp_x + vp_w*0.5 - ed.view_offset.x * ed.view_zoom
    tex_y := vp_y + vp_h*0.5 - ed.view_offset.y * ed.view_zoom
    tex_w := tw * ed.view_zoom
    tex_h := th * ed.view_zoom

    rl.BeginScissorMode(i32(vp_x), i32(vp_y), i32(vp_w), i32(vp_h))

    rl.DrawTexturePro(tex,
        rl.Rectangle{0, 0, tw, th},
        rl.Rectangle{tex_x, tex_y, tex_w, tex_h},
        {0, 0}, 0, rl.WHITE)

    if fw > 0 && fh > 0 && ed.view_zoom * f32(fw) > 6 {
        grid_col := rl.Color{130, 108, 72, 90}
        n_cols_g := int(tex.width)  / fw
        n_rows_g := int(tex.height) / fh
        for c in 0..=n_cols_g {
            gx := tex_x + f32(c * fw) * ed.view_zoom
            rl.DrawLineV({gx, tex_y}, {gx, tex_y + tex_h}, grid_col)
        }
        for r in 0..=n_rows_g {
            gy := tex_y + f32(r * fh) * ed.view_zoom
            rl.DrawLineV({tex_x, gy}, {tex_x + tex_w, gy}, grid_col)
        }

        if ed.sheet.has_clip[ed.active_state] && cols > 0 {
            clip := ed.sheet.clips[ed.active_state]
            for fi in 0..<clip.frame_count {
                af  := clip.start_frame + fi
                fc_ := af %% cols
                fr_ := af /  cols
                frx := tex_x + f32(fc_ * fw) * ed.view_zoom
                fry := tex_y + f32(fr_ * fh) * ed.view_zoom
                frw := f32(fw) * ed.view_zoom
                frh := f32(fh) * ed.view_zoom
                col := ANIM_ED_START_COL; if fi != 0 { col = ANIM_ED_CLIP_COL }
                rl.DrawRectangleLinesEx(rl.Rectangle{frx, fry, frw, frh}, 2, col)
            }
        }

        if ed.sheet.has_clip[ed.active_state] && cols > 0 && fw > 0 && fh > 0 {
            clip := ed.sheet.clips[ed.active_state]
            af   := clip.start_frame
            fc_  := af %% cols
            fr_  := af /  cols
            frx  := tex_x + f32(fc_ * fw) * ed.view_zoom
            fry  := tex_y + f32(fr_ * fh) * ed.view_zoom
            cx_  := frx + f32(ed.sheet.anchor_px_x) * ed.view_zoom
            cy_  := fry + f32(ed.sheet.anchor_px_y) * ed.view_zoom
            arm  := f32(8)
            CROSSHAIR_COL :: rl.Color{ 0, 220, 220, 230 }
            rl.DrawLineV({ cx_ - arm, cy_ }, { cx_ + arm, cy_ }, CROSSHAIR_COL)
            rl.DrawLineV({ cx_, cy_ - arm }, { cx_, cy_ + arm }, CROSSHAIR_COL)
            rl.DrawCircleV({ cx_, cy_ }, 3, CROSSHAIR_COL)

            clip_muzzle := ed.sheet.clips[ed.active_state]
            if clip_muzzle.muzzle_px_x != 0 || clip_muzzle.muzzle_px_y != 0 {
                mx := frx + f32(clip_muzzle.muzzle_px_x) * ed.view_zoom
                my := fry + f32(clip_muzzle.muzzle_px_y) * ed.view_zoom
                PROJECTILE_COL :: rl.Color{ 255, 150, 40, 235 }
                rl.DrawLineV({ mx - arm, my }, { mx + arm, my }, PROJECTILE_COL)
                rl.DrawLineV({ mx, my - arm }, { mx, my + arm }, PROJECTILE_COL)
                rl.DrawCircleV({ mx, my }, 3, PROJECTILE_COL)
            }

            if ed.sheet.has_collision {
                cbx := frx + f32(ed.sheet.collision_px_x) * ed.view_zoom
                cby := fry + f32(ed.sheet.collision_px_y) * ed.view_zoom
                cbw := f32(ed.sheet.collision_px_w) * ed.view_zoom
                cbh := f32(ed.sheet.collision_px_h) * ed.view_zoom
                COLLISION_COL :: rl.Color{ 240, 80, 80, 210 }
                rl.DrawRectangleLinesEx({cbx, cby, cbw, cbh}, 2, COLLISION_COL)
            }
        }

        if over && fw > 0 && fh > 0 && cols > 0 {
            sx := ed.view_offset.x + (mp.x - vp_x - vp_w*0.5) / ed.view_zoom
            sy := ed.view_offset.y + (mp.y - vp_y - vp_h*0.5) / ed.view_zoom
            if sx >= 0 && sy >= 0 && sx < tw && sy < th {
                hc  := int(sx) / fw
                hr  := int(sy) / fh
                af  := hr * cols + hc
                ed.hover_frame = af
                hfx := tex_x + f32(hc * fw) * ed.view_zoom
                hfy := tex_y + f32(hr * fh) * ed.view_zoom
                rl.DrawRectangleLinesEx(
                    rl.Rectangle{hfx, hfy, f32(fw)*ed.view_zoom, f32(fh)*ed.view_zoom},
                    1, rl.Color{230, 230, 230, 140})
                fb: [12]u8
                fn := len(fmt.bprintf(fb[:], "#%d", af)); fb[fn] = 0
                rl.DrawTextEx(g_font, cstring(&fb[0]),
                    {mp.x + uis(7), mp.y - uis(13)}, uis(9), 0.5, ANIM_ED_ACCENT)
            } else {
                ed.hover_frame = -1
            }
        }
    }

    rl.EndScissorMode()

    rl.DrawRectangleLinesEx(rl.Rectangle{vp_x, vp_y, vp_w, vp_h}, 1, ANIM_ED_BORDER)

    {
        zb: [16]u8
        zn := len(fmt.bprintf(zb[:], "%.0f%%", ed.view_zoom * 100)); zb[zn] = 0
        rl.DrawTextEx(g_font, cstring(&zb[0]),
            {vp_x + uis(4), vp_y + vp_h - uis(15)}, uis(9), 0.5, ANIM_ED_MUTED)
    }
}

@(private = "file")
anim_ed_draw_preview :: proc(rp_x, rp_y, rp_w, rp_h: f32, mp: rl.Vector2) {
    ed  := &g_anim_ed
    pad := uis(7)

    rl.DrawRectangle(i32(rp_x), i32(rp_y), i32(rp_w), i32(rp_h), ANIM_ED_PANEL_BG)
    rl.DrawLine(i32(rp_x), i32(rp_y), i32(rp_x), i32(rp_y + rp_h), ANIM_ED_BORDER)

    cy := rp_y + pad
    anim_ed_label(rp_x + pad, cy, "PREVIEW", uis(7), ANIM_ED_MUTED); cy += uis(12)

    if !ed.sprite_ok {
        anim_ed_label(rp_x + pad, cy, "-", uis(9), ANIM_ED_MUTED)
        return
    }

    prev_sz := min(rp_w - pad*2, uis(120))
    prev_x  := rp_x + (rp_w - prev_sz) * 0.5
    prev_y  := cy

    rl.DrawRectangle(i32(prev_x), i32(prev_y), i32(prev_sz), i32(prev_sz), rl.Color{14, 12, 10, 255})
    rl.DrawRectangleLinesEx(rl.Rectangle{prev_x, prev_y, prev_sz, prev_sz}, 1, ANIM_ED_BORDER)

    fw   := ed.sheet.frame_width
    fh   := ed.sheet.frame_height
    cols := ed.sheet.columns
    if ed.sheet.has_clip[ed.active_state] && cols > 0 && fw > 0 && fh > 0 {
        clip  := ed.sheet.clips[ed.active_state]
        af    := clip.start_frame + ed.preview_frame
        fc_   := af %% cols
        fr_   := af /  cols
        src   := rl.Rectangle{ f32(fc_ * fw), f32(fr_ * fh), f32(fw), f32(fh) }
        scale := min(prev_sz / f32(fw), prev_sz / f32(fh))
        dw    := f32(fw) * scale
        dh    := f32(fh) * scale
        dst   := rl.Rectangle{
            prev_x + (prev_sz - dw) * 0.5,
            prev_y + (prev_sz - dh) * 0.5,
            dw, dh,
        }
        rl.DrawTexturePro(ed.sprite_tex, src, dst, {0,0}, 0, rl.WHITE)

        fc_buf: [24]u8
        fc_n := len(fmt.bprintf(fc_buf[:], "%d / %d", ed.preview_frame+1, clip.frame_count))
        fc_buf[fc_n] = 0
        fc_fs := uis(8)
        fc_sz := rl.MeasureTextEx(g_font, cstring(&fc_buf[0]), fc_fs, 0.5)
        rl.DrawTextEx(g_font, cstring(&fc_buf[0]),
            {prev_x + (prev_sz - fc_sz.x)*0.5, prev_y + prev_sz + uis(2)},
            fc_fs, 0.5, ANIM_ED_MUTED)
    }
    cy += prev_sz + uis(15)

    play_lbl := cstring("> Play"); if ed.preview_playing { play_lbl = cstring("|| Pause") }
    play_r   := rl.Rectangle{rp_x + pad, cy, rp_w - pad*2, uis(19)}
    if anim_ed_btn(play_r, play_lbl, mp) {
        ed.preview_playing = !ed.preview_playing
        if ed.preview_playing { ed.preview_frame = 0; ed.preview_elapsed = 0 }
    }
    cy += uis(21)

    state_shorts := [ANIM_STATE_COUNT]cstring{ "Idle", "Walk", "Dodg", "Atk", "Die", "Hit" }
    mini_tab_h   := uis(15)
    stw          := (rp_w - pad*2) / f32(ANIM_STATE_COUNT)
    for si in 0..<ANIM_STATE_COUNT {
        sr     := rl.Rectangle{rp_x + pad + f32(si)*stw, cy, stw - uis(2), mini_tab_h}
        active := ed.active_state == si
        hot    := rl.CheckCollisionPointRec(mp, sr)
        s_bg   := ANIM_ED_INPUT_BG
        if active  { s_bg = ANIM_ED_ACTIVE_BG } else if hot { s_bg = ANIM_ED_HOVER_BG }
        rl.DrawRectangleRec(sr, s_bg)
        if active { rl.DrawRectangleLinesEx(sr, 1, ANIM_ED_ACCENT) }
        s_col := ANIM_ED_ACCENT
        if !active { s_col = ANIM_ED_TEXT if ed.sheet.has_clip[si] else ANIM_ED_MUTED }
        tsz := rl.MeasureTextEx(g_font, state_shorts[si], uis(7), 0.5)
        rl.DrawTextEx(g_font, state_shorts[si],
            {sr.x + (sr.width - tsz.x)*0.5, sr.y + (sr.height - tsz.y)*0.5},
            uis(7), 0.5, s_col)
        if hot && !active && rl.IsMouseButtonReleased(.LEFT) {
            ed.active_state    = si
            ed.preview_frame   = 0
            ed.preview_elapsed = 0
        }
    }
    cy += mini_tab_h + pad

    if ed.sheet.has_clip[ed.active_state] {
        clip := ed.sheet.clips[ed.active_state]
        sb: [48]u8
        loop_s := "no"; if clip.looping { loop_s = "yes" }
        sn := len(fmt.bprintf(sb[:], "fps %.1f  loop %s", clip.fps, loop_s))
        sb[sn] = 0
        rl.DrawTextEx(g_font, cstring(&sb[0]), {rp_x + pad, cy}, uis(8), 0.5, ANIM_ED_MUTED)
    }
}

@(private = "file")
anim_ed_draw_bottom_bar :: proc(bar_x, bar_y, bar_w, bar_h: f32, mp: rl.Vector2) {
    ed  := &g_anim_ed
    pad := uis(7)
    fs  := uis(9)

    rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_w), i32(bar_h), ANIM_ED_PANEL_BG)
    rl.DrawLine(i32(bar_x), i32(bar_y), i32(bar_x + bar_w), i32(bar_y), ANIM_ED_BORDER)

    fh  := uis(17)
    fy  := bar_y + (bar_h - fh) * 0.5
    cx  := bar_x + pad
    lw  := uis(44)
    gap := uis(9)

    anim_ed_label(cx, fy + (fh-fs)*0.5, "frame_w:", fs, ANIM_ED_MUTED); cx += lw
    anim_ed_number_field(rl.Rectangle{cx, fy, uis(35), fh}, .FrameWidth, mp);  cx += uis(35) + gap

    anim_ed_label(cx, fy + (fh-fs)*0.5, "frame_h:", fs, ANIM_ED_MUTED); cx += lw
    anim_ed_number_field(rl.Rectangle{cx, fy, uis(35), fh}, .FrameHeight, mp); cx += uis(35) + gap

    anim_ed_label(cx, fy + (fh-fs)*0.5, "columns:", fs, ANIM_ED_MUTED); cx += lw
    anim_ed_number_field(rl.Rectangle{cx, fy, uis(29), fh}, .Columns, mp);    cx += uis(29) + gap

    if ed.sprite_ok {
        tsz_buf: [32]u8
        tsz_n := len(fmt.bprintf(tsz_buf[:], "tex %dx%d", ed.sprite_tex.width, ed.sprite_tex.height))
        tsz_buf[tsz_n] = 0
        rl.DrawTextEx(g_font, cstring(&tsz_buf[0]), {cx, fy + (fh - uis(8))*0.5}, uis(8), 0.5, ANIM_ED_MUTED)
    }

    btn_h := uis(20)
    btn_y := bar_y + (bar_h - btn_h) * 0.5
    sav_w := uis(80)
    rev_w := uis(51)
    b_gap := uis(5)
    sav_x := bar_w - sav_w - rev_w - b_gap - pad
    rev_x := bar_w - rev_w - pad

    sav_lbl := cstring("Save JSON"); if ed.dirty { sav_lbl = cstring("* Save JSON") }
    if anim_ed_btn(rl.Rectangle{sav_x, btn_y, sav_w, btn_h}, sav_lbl, mp) {
        anim_ed_commit_field(); anim_editor_save()
    }
    if anim_ed_btn(rl.Rectangle{rev_x, btn_y, rev_w, btn_h}, cstring("Revert"), mp) {
        anim_editor_revert()
    }
}

draw_anim_editor :: proc() {
    if !g_anim_ed.open { return }
    ed := &g_anim_ed
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    mp := rl.GetMousePosition()

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), ANIM_ED_BG)

    hdr_h := uis(ANIM_ED_HDR_H)
    bot_h := uis(ANIM_ED_BOT_H)
    lp_w  := uis(ANIM_ED_PANEL_W)
    rp_w  := uis(ANIM_ED_PREV_W)
    mid_y := hdr_h
    mid_h := sh - hdr_h - bot_h
    rp_x  := sw - rp_w
    vp_x  := lp_w
    vp_w  := rp_x - lp_w
    bot_y := sh - bot_h

    anim_ed_draw_header(sw, 0, hdr_h, mp)
    anim_ed_draw_left_panel(0, mid_y, lp_w, mid_h, mp)
    anim_ed_draw_viewport(vp_x, mid_y, vp_w, mid_h, mp)
    anim_ed_draw_preview(rp_x, mid_y, rp_w, mid_h, mp)
    anim_ed_draw_bottom_bar(0, bot_y, sw, bot_h, mp)

    if rl.IsMouseButtonPressed(.LEFT) {
        in_lp  := rl.CheckCollisionPointRec(mp, rl.Rectangle{0, mid_y, lp_w, mid_h})
        in_bot := rl.CheckCollisionPointRec(mp, rl.Rectangle{0, bot_y, sw,  bot_h})
        if !in_lp && !in_bot {
            if ed.focused_field != .None && ed.focused_field != .Key {
                anim_ed_commit_field(); ed.focused_field = .None
            }
        }
    }

    if ed.toast_timer > 0 && ed.toast_len > 0 {
        a := u8(clamp(int(ed.toast_timer * 200), 0, 255))
        ed.toast_msg[ed.toast_len] = 0
        msg := cstring(&ed.toast_msg[0])
        tfs := uis(12)
        tsz := rl.MeasureTextEx(g_font, msg, tfs, 0.5)
        tx  := sw*0.5 - tsz.x*0.5
        ty  := sh*0.5 - tsz.y*0.5
        tp  := uis(9)
        rl.DrawRectangleRounded(
            rl.Rectangle{tx - tp, ty - tp*0.6, tsz.x + tp*2, tsz.y + tp*1.2},
            0.4, 8, rl.Color{18, 46, 18, a})
        rl.DrawTextEx(g_font, msg, {tx, ty}, tfs, 0.5, rl.Color{130, 205, 100, a})
    }
}
