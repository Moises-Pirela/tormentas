package main

import      "core:fmt"
import      "core:path/filepath"
import      "core:strings"
import im   "../deps/imgui/imgui"
import rl   "vendor:raylib"

ANIM_ED_KEY_CAP :: 64

ANIM_ED_GRID_COL      :: 0x5a_48_6c_82
ANIM_ED_CLIP_COL      :: 0x6e_3a_8c_be
ANIM_ED_START_COL     :: 0xc8_64_c8_64
ANIM_ED_HOVER_COL     :: 0x8c_e6_e6_e6
ANIM_ED_ANCHOR_COL    :: 0xe6_dc_dc_00
ANIM_ED_MUZZLE_COL    :: 0xeb_28_96_ff
ANIM_ED_COLLISION_COL :: 0xd2_50_50_f0

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
    hover_frame:     int,

    active_state:    int,
    select_tab:      bool,

    preview_playing: bool,
    preview_frame:   int,
    preview_elapsed: f32,

    found_keys:      [dynamic]string,

    toast_msg:       [64]u8,
    toast_len:       int,
    toast_timer:     f32,
    first_open:      bool,
    fit_pending:     bool,
}

g_anim_ed: AnimEditorState

anim_editor_open :: proc() {
    if g_anim_ed.open { return }
    ed := &g_anim_ed
    ed.open        = true
    ed.view_zoom   = 2.0
    ed.hover_frame = -1
    ed.first_open  = true
    if ed.found_keys == nil {
        ed.found_keys = make([dynamic]string)
    }
    anim_editor_scan_keys()
}

anim_editor_close :: proc() {
    g_anim_ed.open = false
}

@(private = "file")
anim_editor_toast :: proc(msg: string) {
    ed := &g_anim_ed
    n  := min(len(msg), len(ed.toast_msg) - 1)
    copy(ed.toast_msg[:], msg[:n])
    ed.toast_len   = n
    ed.toast_timer = 2.5
}

@(private = "file")
anim_ed_key_stem :: proc() -> string {
    return string(g_anim_ed.key_buf[:g_anim_ed.key_len])
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
    ed.select_tab = true
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

    ed.fit_pending   = true
    ed.view_offset   = { f32(tex.width) * 0.5, f32(tex.height) * 0.5 }
    ed.view_zoom     = max(2.0, uis(240) / f32(max(tex.width, 1)))
    ed.preview_frame   = 0
    ed.preview_elapsed = 0
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
                    ed.preview_frame   = max(clip.frame_count - 1, 0)
                    ed.preview_elapsed = 0
                    break
                }
            }
        }
    }

    if devui_wants_text() { return }
    if rl.IsKeyPressed(.ESCAPE) { anim_editor_close(); return }
    if platform_cmd_down() && rl.IsKeyPressed(.S) { anim_editor_save() }
}

@(private = "file")
_ae_clip :: proc() -> ^AnimClipDef {
    return &g_anim_ed.sheet.clips[g_anim_ed.active_state]
}

@(private = "file")
_ae_int :: proc(label: cstring, v: ^int, lo, hi: int, touch_clip := false, touch_collision := false) {
    ed := &g_anim_ed
    if ui_input_i32(label, v, lo, max(hi, lo)) {
        ed.dirty = true
        if touch_clip      { ed.sheet.has_clip[ed.active_state] = true; ed.preview_frame = 0 }
        if touch_collision { ed.sheet.has_collision = true }
    }
}

@(private = "file")
_ae_set_state :: proc(si: int) {
    ed := &g_anim_ed
    if si == ed.active_state { return }
    ed.active_state    = si
    ed.preview_frame   = 0
    ed.preview_elapsed = 0
}

@(private = "file")
_ae_settings :: proc() {
    ed := &g_anim_ed

    im.SeparatorText("Sprite")
    im.SetNextItemWidth(-1)
    if ui_input_buf("##aekey", ed.key_buf[:], &ed.key_len, { .EnterReturnsTrue }, "sprite key (Enter loads)") {
        anim_editor_load(anim_ed_key_stem())
    }
    if im.BeginCombo("##aebrowse", "Browse sprites...", { .HeightLarge }) {
        filter := strings.to_lower(anim_ed_key_stem(), context.temp_allocator)
        for k in ed.found_keys {
            if filter != "" && !strings.contains(strings.to_lower(k, context.temp_allocator), filter) { continue }
            if im.Selectable(cs(k), k == anim_ed_key_stem()) {
                ed.key_len = min(len(k), ANIM_ED_KEY_CAP - 1)
                copy(ed.key_buf[:], k[:ed.key_len])
                anim_editor_load(anim_ed_key_stem())
            }
        }
        im.EndCombo()
    }

    bw := (im.GetContentRegionAvail().x - 2 * im.GetStyle().ItemSpacing.x) / 3
    im.BeginDisabled(!ed.sprite_ok)
    if im.Button(ed.dirty ? "Save*" : "Save", { bw, 0 }) { anim_editor_save() }
    ui_tooltip("Ctrl+S  (Cmd+S on macOS)")
    im.SameLine()
    if im.Button("Revert", { bw, 0 }) { anim_editor_revert() }
    im.EndDisabled()
    im.SameLine()
    if im.Button("Rescan", { bw, 0 }) { anim_editor_scan_keys() }
    im.BeginDisabled(!ed.sprite_ok)
    if im.Button("Fit sheet to view", { -1, 0 }) { ed.fit_pending = true }
    im.EndDisabled()

    if ed.toast_timer > 0 && ed.toast_len > 0 {
        ui_text_col(DEVUI_GREEN, "%s", string(ed.toast_msg[:ed.toast_len]))
    } else if ed.dirty {
        ui_text_col(DEVUI_RED, "unsaved changes")
    } else if ed.sprite_ok {
        ui_hint("texture %dx%d", ed.sprite_tex.width, ed.sprite_tex.height)
    } else {
        ui_hint("No sprite loaded")
    }
    if !ed.sprite_ok { return }

    im.SeparatorText("Sheet")
    _ae_int("Frame width",  &ed.sheet.frame_width,  1, 8192)
    _ae_int("Frame height", &ed.sheet.frame_height, 1, 8192)
    _ae_int("Columns",      &ed.sheet.columns,      1, 1024)

    im.SeparatorText("State")
    if im.BeginTabBar("##aestates", { .FittingPolicyScroll }) {
        for si in 0..<ANIM_STATE_COUNT {
            flags: im.TabItemFlags
            if ed.select_tab && si == ed.active_state { flags += { .SetSelected } }
            label := fmt.ctprintf("%s%s###st%d", ANIM_STATE_NAMES[si], ed.sheet.has_clip[si] ? "" : " (off)", si)
            if im.BeginTabItem(label, nil, flags) {
                if !ed.select_tab { _ae_set_state(si) }
                im.EndTabItem()
            }
        }
        ed.select_tab = false
        im.EndTabBar()
    }

    clip := _ae_clip()
    if im.Checkbox("Clip enabled", &ed.sheet.has_clip[ed.active_state]) { ed.dirty = true }
    _ae_int("Start frame", &clip.start_frame, 0, 1 << 20, true)
    _ae_int("Frame count", &clip.frame_count, 1, 1 << 16, true)
    fps := clip.fps
    if im.InputFloat("FPS", &fps, 1, 5, "%.1f") && fps > 0 {
        clip.fps = fps
        ed.sheet.has_clip[ed.active_state] = true
        ed.dirty = true
    }
    if im.Checkbox("Looping", &clip.looping) {
        ed.sheet.has_clip[ed.active_state] = true
        ed.dirty = true
    }

    fw := max(ed.sheet.frame_width, 1)
    fh := max(ed.sheet.frame_height, 1)
    im.SeparatorText("Anchor")
    _ae_int("Anchor X", &ed.sheet.anchor_px_x, 0, fw)
    _ae_int("Anchor Y", &ed.sheet.anchor_px_y, 0, fh)
    im.SeparatorText("Projectile spawn")
    _ae_int("Muzzle X", &clip.muzzle_px_x, 0, fw, true)
    _ae_int("Muzzle Y", &clip.muzzle_px_y, 0, fh, true)
    im.SeparatorText("Collision box")
    if im.Checkbox("Has collision box", &ed.sheet.has_collision) { ed.dirty = true }
    im.BeginDisabled(!ed.sheet.has_collision)
    _ae_int("Box X", &ed.sheet.collision_px_x, 0, fw, false, true)
    _ae_int("Box Y", &ed.sheet.collision_px_y, 0, fh, false, true)
    _ae_int("Box W", &ed.sheet.collision_px_w, 1, max(fw - ed.sheet.collision_px_x, 1), false, true)
    _ae_int("Box H", &ed.sheet.collision_px_h, 1, max(fh - ed.sheet.collision_px_y, 1), false, true)
    im.EndDisabled()

    im.Spacing()
    ui_hint("Sheet: click a frame to set the start frame.")
    ui_hint("Ctrl-drag sets the anchor, Shift-drag the muzzle.")
    ui_hint("Right/middle drag pans, wheel zooms.")
}

@(private = "file")
_ae_canvas :: proc() {
    ed   := &g_anim_ed
    size := im.GetContentRegionAvail()
    if size.x < 32 || size.y < 32 { return }
    origin := im.GetCursorScreenPos()
    im.InvisibleButton("##aecanvas", size, { .MouseButtonLeft, .MouseButtonRight, .MouseButtonMiddle })
    hovered := im.IsItemHovered()
    active  := im.IsItemActive()
    dl      := im.GetWindowDrawList()
    p0      := origin
    p1      := im.Vec2{ origin.x + size.x, origin.y + size.y }

    im.DrawList_AddRectFilled(dl, p0, p1, 0xff_0c_0f_12)
    im.DrawList_PushClipRect(dl, p0, p1, true)
    defer im.DrawList_PopClipRect(dl)

    if !ed.sprite_ok {
        msg: cstring = "Load a sprite to see the sheet"
        ts := im.CalcTextSize(msg)
        im.DrawList_AddText(dl, { origin.x + (size.x - ts.x) * 0.5, origin.y + (size.y - ts.y) * 0.5 }, 0xff_80_90_a0, msg)
        return
    }

    tex  := ed.sprite_tex
    tw   := f32(tex.width)
    th   := f32(tex.height)
    fw   := ed.sheet.frame_width
    fh   := ed.sheet.frame_height
    cols := ed.sheet.columns
    io   := im.GetIO()
    mp   := im.GetMousePos()

    if ed.fit_pending && tw > 0 && th > 0 {
        ed.view_zoom   = clamp(min(size.x / tw, size.y / th) * 0.95, 0.125, 64)
        ed.view_offset = { tw * 0.5, th * 0.5 }
        ed.fit_pending = false
    }

    if hovered && io.MouseWheel != 0 {
        old_z := ed.view_zoom
        ed.view_zoom = clamp(ed.view_zoom * (1 + io.MouseWheel * 0.15), 0.125, 64)
        lx := mp.x - origin.x - size.x * 0.5
        ly := mp.y - origin.y - size.y * 0.5
        ed.view_offset.x += lx / old_z - lx / ed.view_zoom
        ed.view_offset.y += ly / old_z - ly / ed.view_zoom
    }
    if active && (im.IsMouseDragging(.Right, 0) || im.IsMouseDragging(.Middle, 0)) {
        ed.view_offset.x -= io.MouseDelta.x / ed.view_zoom
        ed.view_offset.y -= io.MouseDelta.y / ed.view_zoom
    }
    ed.view_offset.x = clamp(ed.view_offset.x, -tw, tw * 2)
    ed.view_offset.y = clamp(ed.view_offset.y, -th, th * 2)

    z     := ed.view_zoom
    tex_x := origin.x + size.x * 0.5 - ed.view_offset.x * z
    tex_y := origin.y + size.y * 0.5 - ed.view_offset.y * z

    sx := (mp.x - tex_x) / z
    sy := (mp.y - tex_y) / z
    inside := sx >= 0 && sy >= 0 && sx < tw && sy < th && fw > 0 && fh > 0

    if active && inside && im.IsMouseDown(.Left) {
        lx := clamp(int(sx) %% fw, 0, fw)
        ly := clamp(int(sy) %% fh, 0, fh)
        shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
        switch {
        case platform_cmd_down():
            if ed.sheet.anchor_px_x != lx || ed.sheet.anchor_px_y != ly {
                ed.sheet.anchor_px_x, ed.sheet.anchor_px_y = lx, ly
                ed.dirty = true
            }
        case shift:
            clip := _ae_clip()
            if clip.muzzle_px_x != lx || clip.muzzle_px_y != ly {
                clip.muzzle_px_x, clip.muzzle_px_y = lx, ly
                ed.sheet.has_clip[ed.active_state] = true
                ed.dirty = true
            }
        case im.IsMouseClicked(.Left) && cols > 0:
            _ae_clip().start_frame = (int(sy) / fh) * cols + (int(sx) / fw)
            ed.sheet.has_clip[ed.active_state] = true
            ed.dirty         = true
            ed.preview_frame = 0
        }
    }

    im.DrawList_AddImage(dl, devui_texture(tex), { tex_x, tex_y }, { tex_x + tw * z, tex_y + th * z })

    if fw > 0 && fh > 0 && z * f32(fw) > 6 {
        for c in 0..=int(tex.width) / fw {
            gx := tex_x + f32(c * fw) * z
            im.DrawList_AddLine(dl, { gx, tex_y }, { gx, tex_y + th * z }, ANIM_ED_GRID_COL)
        }
        for r in 0..=int(tex.height) / fh {
            gy := tex_y + f32(r * fh) * z
            im.DrawList_AddLine(dl, { tex_x, gy }, { tex_x + tw * z, gy }, ANIM_ED_GRID_COL)
        }

        if ed.sheet.has_clip[ed.active_state] && cols > 0 {
            clip := ed.sheet.clips[ed.active_state]
            for fi in 0..<clip.frame_count {
                af := clip.start_frame + fi
                fx := tex_x + f32((af %% cols) * fw) * z
                fy := tex_y + f32((af / cols) * fh) * z
                im.DrawList_AddRect(dl, { fx, fy }, { fx + f32(fw) * z, fy + f32(fh) * z },
                    ANIM_ED_START_COL if fi == 0 else ANIM_ED_CLIP_COL, 0, 2)
            }

            fx := tex_x + f32((clip.start_frame %% cols) * fw) * z
            fy := tex_y + f32((clip.start_frame / cols) * fh) * z
            _ae_cross(dl, { fx + f32(ed.sheet.anchor_px_x) * z, fy + f32(ed.sheet.anchor_px_y) * z }, ANIM_ED_ANCHOR_COL)
            if clip.muzzle_px_x != 0 || clip.muzzle_px_y != 0 {
                _ae_cross(dl, { fx + f32(clip.muzzle_px_x) * z, fy + f32(clip.muzzle_px_y) * z }, ANIM_ED_MUZZLE_COL)
            }
            if ed.sheet.has_collision {
                bx := fx + f32(ed.sheet.collision_px_x) * z
                by := fy + f32(ed.sheet.collision_px_y) * z
                im.DrawList_AddRect(dl, { bx, by },
                    { bx + f32(ed.sheet.collision_px_w) * z, by + f32(ed.sheet.collision_px_h) * z },
                    ANIM_ED_COLLISION_COL, 0, 2)
            }
        }

        ed.hover_frame = -1
        if hovered && inside && cols > 0 {
            hc := int(sx) / fw
            hr := int(sy) / fh
            ed.hover_frame = hr * cols + hc
            hx := tex_x + f32(hc * fw) * z
            hy := tex_y + f32(hr * fh) * z
            im.DrawList_AddRect(dl, { hx, hy }, { hx + f32(fw) * z, hy + f32(fh) * z }, ANIM_ED_HOVER_COL)
            im.DrawList_AddText(dl, { mp.x + 12, mp.y - 16 }, 0xff_3a_b4_e0, fmt.ctprintf("#%d", ed.hover_frame))
        }
    }

    im.DrawList_AddText(dl, { origin.x + 6, origin.y + size.y - 20 }, 0xff_90_a0_a8, fmt.ctprintf("%.0f%%", z * 100))
}

@(private = "file")
_ae_cross :: proc(dl: ^im.DrawList, c: im.Vec2, col: u32) {
    ARM :: f32(8)
    im.DrawList_AddLine(dl, { c.x - ARM, c.y }, { c.x + ARM, c.y }, col)
    im.DrawList_AddLine(dl, { c.x, c.y - ARM }, { c.x, c.y + ARM }, col)
    im.DrawList_AddCircleFilled(dl, c, 3, col)
}

@(private = "file")
_ae_preview :: proc() {
    ed := &g_anim_ed
    im.SeparatorText("Preview")
    if !ed.sprite_ok { ui_hint("-"); return }

    fw, fh, cols := ed.sheet.frame_width, ed.sheet.frame_height, ed.sheet.columns
    side := min(im.GetContentRegionAvail().x, 220)
    if ed.sheet.has_clip[ed.active_state] && cols > 0 && fw > 0 && fh > 0 {
        clip := ed.sheet.clips[ed.active_state]
        af   := clip.start_frame + ed.preview_frame
        tw   := f32(ed.sprite_tex.width)
        th   := f32(ed.sprite_tex.height)
        u0   := f32((af %% cols) * fw) / tw
        v0   := f32((af / cols) * fh) / th
        u1   := u0 + f32(fw) / tw
        v1   := v0 + f32(fh) / th
        scale := min(side / f32(fw), side / f32(fh))
        im.ImageWithBg(devui_texture(ed.sprite_tex), { f32(fw) * scale, f32(fh) * scale }, { u0, v0 }, { u1, v1 }, { 0.05, 0.05, 0.06, 1 })
        ui_hint("frame %d / %d   fps %.1f   %s", ed.preview_frame + 1, clip.frame_count, clip.fps, clip.looping ? "loop" : "once")
    } else {
        ui_hint("Clip is disabled for this state.")
    }
    if im.Button(ed.preview_playing ? "Pause" : "Play", { -1, 0 }) {
        ed.preview_playing = !ed.preview_playing
        if ed.preview_playing { ed.preview_frame = 0; ed.preview_elapsed = 0 }
    }
    if ed.hover_frame >= 0 { ui_hint("hover frame #%d", ed.hover_frame) }
}

anim_editor_ui :: proc() {
    ed := &g_anim_ed
    if !ed.open { return }
    vp := im.GetMainViewport()
    if ed.first_open {
        im.SetNextWindowPos({ vp.WorkPos.x + 24, vp.WorkPos.y + 24 }, .FirstUseEver)
        im.SetNextWindowSize({ vp.WorkSize.x - 48, vp.WorkSize.y - 48 }, .FirstUseEver)
        ed.first_open = false
    }
    open := true
    defer im.End()
    if !im.Begin("Animation Editor", &open, { .NoScrollbar }) {
        if !open { anim_editor_close() }
        return
    }
    if !open { anim_editor_close(); return }

    if im.BeginTable("##aelayout", 3, im.TableFlags_Resizable | im.TableFlags_BordersInnerV, { 0, -1 }) {
        im.TableSetupColumn("settings", { .WidthFixed }, 280)
        im.TableSetupColumn("sheet",    { .WidthStretch })
        im.TableSetupColumn("preview",  { .WidthFixed }, 230)
        im.TableNextRow()
        im.TableNextColumn()
        if im.BeginChild("##aeset") { _ae_settings() }
        im.EndChild()
        im.TableNextColumn()
        _ae_canvas()
        im.TableNextColumn()
        if im.BeginChild("##aeprev") { _ae_preview() }
        im.EndChild()
        im.EndTable()
    }
}

anim_editor_open_sprite :: proc(stem: string) {
    anim_editor_open()
    ed := &g_anim_ed
    ed.key_len = min(len(stem), ANIM_ED_KEY_CAP - 1)
    copy(ed.key_buf[:], stem[:ed.key_len])
    anim_editor_load(stem)
}
