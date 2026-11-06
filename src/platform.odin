package main

import    "core:fmt"
import    "core:os"
import    "core:path/filepath"
import    "core:strings"
import rl "vendor:raylib"

APP_DIR_NAME       :: "Tormentas"
WINDOW_DEFAULT_W   :: 1600
WINDOW_DEFAULT_H   :: 900
WINDOW_MIN_W       :: 960
WINDOW_MIN_H       :: 540
WINDOW_MODE_FULL   :: "fullscreen"
WINDOW_MODE_WINDOW :: "windowed"

DisplaySettings :: struct {
    mode:     string,
    window_w: i32,
    window_h: i32,
}

g_user_dir:       string
g_fullscreen:     bool
g_windowed_size:  [2]i32

user_data_dir :: proc() -> string {
    if g_user_dir != "" { return g_user_dir }
    when ODIN_OS == .Darwin {
        home := os.get_env("HOME", context.temp_allocator)
        if home != "" {
            g_user_dir, _ = filepath.join({ home, "Library", "Application Support", APP_DIR_NAME })
            return g_user_dir
        }
    }
    g_user_dir = strings.clone(".")
    return g_user_dir
}

user_path :: proc(rel: string) -> string {
    out, _ := filepath.join({ user_data_dir(), rel }, context.temp_allocator)
    return out
}

ensure_user_dir :: proc(rel_dir: string) {
    os.make_directory_all(user_path(rel_dir))
}

migrate_legacy_user_files :: proc() {
    when ODIN_OS != .Darwin { return }
    for rel in ([]string{ "save/characters.bin", "save/player.bin" }) {
        dst := user_path(rel)
        if os.exists(dst) || !os.exists(rel) { continue }
        data, err := os.read_entire_file(rel, context.temp_allocator)
        if err != nil { continue }
        ensure_user_dir(filepath.dir(rel))
        if write_game_file(dst, data) {
            fmt.eprintf("[save] migrated %s to %s\n", rel, dst)
        }
    }
}

platform_default_fullscreen :: proc() -> bool {
    return ODIN_OS == .Darwin
}

@(private = "file")
_wants_fullscreen :: proc() -> bool {
    switch g_binds.display.mode {
    case WINDOW_MODE_FULL:   return true
    case WINDOW_MODE_WINDOW: return false
    }
    return platform_default_fullscreen()
}

@(private = "file")
_monitor_size :: proc() -> [2]i32 {
    m := rl.GetCurrentMonitor()
    return { rl.GetMonitorWidth(m), rl.GetMonitorHeight(m) }
}

@(private = "file")
_fit_window :: proc(size: [2]i32) -> [2]i32 {
    mon := _monitor_size()
    w, h := size[0], size[1]
    if w <= 0 || h <= 0 { w, h = WINDOW_DEFAULT_W, WINDOW_DEFAULT_H }
    if mon[0] > 0 && mon[1] > 0 {
        max_w := i32(f32(mon[0]) * 0.92)
        max_h := i32(f32(mon[1]) * 0.88)
        if w > max_w || h > max_h {
            k := min(f32(max_w) / f32(w), f32(max_h) / f32(h))
            w  = i32(f32(w) * k)
            h  = i32(f32(h) * k)
        }
    }
    return { max(w, WINDOW_MIN_W), max(h, WINDOW_MIN_H) }
}

@(private = "file")
_center_window :: proc(size: [2]i32) {
    m   := rl.GetCurrentMonitor()
    pos := rl.GetMonitorPosition(m)
    mon := _monitor_size()
    rl.SetWindowPosition(i32(pos.x) + (mon[0] - size[0]) / 2, i32(pos.y) + (mon[1] - size[1]) / 2)
}

platform_init_window :: proc(title: cstring) {
    rl.SetConfigFlags({ .WINDOW_RESIZABLE, .VSYNC_HINT })
    rl.InitWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, title)
    rl.SetWindowMinSize(WINDOW_MIN_W, WINDOW_MIN_H)

    g_windowed_size = _fit_window({ g_binds.display.window_w, g_binds.display.window_h })
    rl.SetWindowSize(g_windowed_size[0], g_windowed_size[1])
    _center_window(g_windowed_size)
    native_fullscreen_prepare()

    if _wants_fullscreen() { platform_set_fullscreen(true) }
}

platform_set_fullscreen :: proc(on: bool) {
    when ODIN_OS == .Darwin {
        if on != native_is_fullscreen() {
            if on { g_windowed_size = { rl.GetScreenWidth(), rl.GetScreenHeight() } }
            native_toggle_fullscreen()
        }
    } else {
        if on == g_fullscreen { return }
        if on {
            if !rl.IsWindowState({ .BORDERLESS_WINDOWED_MODE }) {
                g_windowed_size = { rl.GetScreenWidth(), rl.GetScreenHeight() }
            }
            rl.ToggleBorderlessWindowed()
        } else {
            if rl.IsWindowState({ .BORDERLESS_WINDOWED_MODE }) { rl.ToggleBorderlessWindowed() }
            g_windowed_size = _fit_window(g_windowed_size)
            rl.SetWindowSize(g_windowed_size[0], g_windowed_size[1])
            _center_window(g_windowed_size)
        }
    }
    g_fullscreen = on
    g_binds.display.mode = WINDOW_MODE_FULL if on else WINDOW_MODE_WINDOW
}

platform_set_window_size :: proc(w, h: i32) {
    if g_fullscreen { return }
    g_windowed_size = _fit_window({ w, h })
    rl.SetWindowSize(g_windowed_size[0], g_windowed_size[1])
    _center_window(g_windowed_size)
}

platform_window_fits :: proc(w, h: i32) -> bool {
    mon := _monitor_size()
    return mon[0] <= 0 || (w <= mon[0] && h <= mon[1])
}

platform_update_window :: proc() {
    when ODIN_OS == .Darwin {
        g_fullscreen = native_is_fullscreen()
    }
    if !g_fullscreen && rl.IsWindowResized() {
        g_windowed_size = { rl.GetScreenWidth(), rl.GetScreenHeight() }
    }
    toggle := false
    when ODIN_OS == .Darwin {
        cmd  := rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER)
        ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
        toggle = cmd && ctrl && rl.IsKeyPressed(.F)
    } else {
        alt := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
        toggle = alt && (rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER))
    }
    if toggle {
        platform_set_fullscreen(!g_fullscreen)
        save_config()
    }
}

platform_store_display_settings :: proc() {
    g_binds.display.mode     = WINDOW_MODE_FULL if g_fullscreen else WINDOW_MODE_WINDOW
    g_binds.display.window_w = g_windowed_size[0]
    g_binds.display.window_h = g_windowed_size[1]
}

platform_cmd_down :: proc() -> bool {
    ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    when ODIN_OS == .Darwin {
        return ctrl || rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER)
    } else {
        return ctrl
    }
}

g_window_probe_dir:   string
g_window_probe_frame: int

window_probe_from_args :: proc() {
    for a, i in os.args {
        if a == "--tools-probe" && i + 1 < len(os.args) {
            g_tools_probe = true
            g_window_probe_dir = os.args[i + 1]
            g_user_dir         = filepath.join({ g_window_probe_dir, "userdata" }) or_else ""
        }
        if a == "--window-probe" && i + 1 < len(os.args) {
            g_window_probe_dir = os.args[i + 1]
            g_user_dir         = filepath.join({ g_window_probe_dir, "userdata" }) or_else ""
        }
    }
}

@(private = "file")
_probe_log :: proc(tag: string) {
    fmt.printf("[probe] %-14s fullscreen=%v rl_fullscreen=%v screen=%dx%d render=%dx%d monitor=%dx%d dpi=%.2f resized=%v\n",
        tag, g_fullscreen, rl.IsWindowFullscreen(), rl.GetScreenWidth(), rl.GetScreenHeight(),
        rl.GetRenderWidth(), rl.GetRenderHeight(), _monitor_size()[0], _monitor_size()[1],
        rl.GetWindowScaleDPI().x, rl.IsWindowResized())
}

@(private = "file")
_probe_shot :: proc(tag: string) {
    path := strings.clone_to_cstring(fmt.tprintf("%s/%s.png", g_window_probe_dir, tag), context.temp_allocator)
    img  := rl.LoadImageFromScreen()
    defer rl.UnloadImage(img)
    rl.ExportImage(img, path)
}

g_tools_probe: bool

tools_probe_tick :: proc(f: int) -> (done: bool) {
    switch f {
    case 5:   probe_start_singleplayer()
    case 40:  editor_toggle()
    case 90:  _probe_shot("t1_editor")
    case 91:
        for d, i in g_entity_defs { if d.name == "enemy_brute" { g_ed_def_idx = i } }
        ed_entity_place({ 160, 96 })
        g_ed_tool = .Select
    case 100:
        h := ed_gizmo_probe_handle()
        rl.SetMousePosition(i32(h.x), i32(h.y))
    case 129: fmt.printf("[probe] selected=%d entities=%d tool=%v hover=%v\n", g_ed_sel_entity, len(g_level_data.entities), g_ed_tool, ed_gizmo_hover())
    case 130: _probe_shot("t2_inspector")
    case 131: ed_gizmo_probe_drag(128, 64)
    case 140: _probe_shot("t2b_gizmo_drag")
    case 141:
        ed_gizmo_cancel()
        g_ed_tool       = .Paint
        g_ed_brush      = .HubCollision
        g_ed_brush_size = g_ed_cell_size * 4
        rl.SetMousePosition(rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2 + 60)
    case 150:
        c := ed_mouse_cell()
        ed_stroke_begin(.Paint, .LEFT)
        ed_stroke_update({ c[0] - 12, c[1] - 2 })
        ed_stroke_update(c)
    case 165: _probe_shot("t2c_brush_stroke")
    case 166:
        ed_stroke_end()
        g_ed_tool = .Erase
    case 175: _probe_shot("t2d_erase_cursor")
    case 176:
        g_ed_tool = .Select
        console_set_open(true)
        console_log("> help")
        console_log("probe: console line")
        g_light_widget_open = true
        dbg_inspector_toggle()
    case 200: _probe_shot("t3_tools")
    case 201:
        console_set_open(false)
        g_light_widget_open = false
        g_dbg_insp_open     = false
        editor_toggle()
        anim_editor_open_sprite("player_sheriff")
    case 260: _probe_shot("t4_anim_editor")
    case 261:
        anim_editor_close()
        enter_raid(&g_sim.world, 1)
    case 290: editor_toggle()
    case 320:
        g_ed_tool       = .Paint
        g_ed_brush      = .Oil
        g_ed_brush_size = TILE_SIZE * 3
        rl.SetMousePosition(rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2)
    case 350: _probe_shot("t5_raid_brush")
    case 351: return true
    }
    return false
}

window_probe_tick :: proc() -> (done: bool) {
    if g_window_probe_dir == "" { return false }
    if g_tools_probe {
        g_window_probe_frame += 1
        return tools_probe_tick(g_window_probe_frame - 1)
    }
    f := g_window_probe_frame
    g_window_probe_frame += 1
    switch f {
    case 5:   probe_start_singleplayer()
    case 90:  _probe_log("startup");    _probe_shot("1_startup")
    case 91:  platform_set_fullscreen(false)
    case 180: _probe_log("windowed");   _probe_shot("2_windowed")
    case 181: platform_set_window_size(1100, 700)
    case 220: _probe_log("resized");    _probe_shot("3_resized")
    case 221: platform_set_window_size(4000, 3000)
    case 260: _probe_log("oversized")
    case 261: platform_set_fullscreen(true)
    case 350: _probe_log("fullscreen"); _probe_shot("4_fullscreen")
    case 351: return true
    }
    return false
}
