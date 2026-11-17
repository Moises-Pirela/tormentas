package main

import    "core:fmt"
import    "core:os"
import    "core:path/filepath"
import    "core:strings"
import gfx "gfx"

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

// The window to open, from the saved display settings. Read before the window exists, because
// sokol_app takes size and mode at creation and has no API to change them afterwards.
platform_window_desc :: proc(title: cstring) -> gfx.Window_Desc {
    w := g_binds.display.window_w
    h := g_binds.display.window_h
    if w < WINDOW_MIN_W || h < WINDOW_MIN_H { w, h = WINDOW_DEFAULT_W, WINDOW_DEFAULT_H }
    g_windowed_size = { w, h }
    return { width = w, height = h, title = title, fullscreen = _wants_fullscreen() }
}

platform_init_window :: proc(title: cstring) {
    gfx.window_init(platform_window_desc(title))
    g_fullscreen = gfx.window_is_fullscreen()
}

platform_set_fullscreen :: proc(on: bool) {
    if on != gfx.window_is_fullscreen() {
        if on && !g_fullscreen { g_windowed_size = { gfx.screen_width(), gfx.screen_height() } }
        gfx.window_toggle_fullscreen()
    }
    g_fullscreen = on
    g_binds.display.mode = WINDOW_MODE_FULL if on else WINDOW_MODE_WINDOW
}

// Tracks the window and the fullscreen hotkey. The toggle may also come from the OS (the green
// button on macOS), so the flag is re-read every frame rather than only written here.
platform_update_window :: proc() {
    was := g_fullscreen
    g_fullscreen = gfx.window_is_fullscreen()
    if !g_fullscreen && gfx.window_resized() {
        g_windowed_size = { gfx.screen_width(), gfx.screen_height() }
    }
    if was != g_fullscreen {
        g_binds.display.mode = WINDOW_MODE_FULL if g_fullscreen else WINDOW_MODE_WINDOW
        save_config()
    }

    toggle := false
    when ODIN_OS == .Darwin {
        cmd  := gfx.key_down(.LEFT_SUPER) || gfx.key_down(.RIGHT_SUPER)
        ctrl := gfx.key_down(.LEFT_CONTROL) || gfx.key_down(.RIGHT_CONTROL)
        toggle = cmd && ctrl && gfx.key_pressed(.F)
    } else {
        alt := gfx.key_down(.LEFT_ALT) || gfx.key_down(.RIGHT_ALT)
        toggle = alt && (gfx.key_pressed(.ENTER) || gfx.key_pressed(.KP_ENTER))
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
    ctrl := gfx.key_down(.LEFT_CONTROL) || gfx.key_down(.RIGHT_CONTROL)
    when ODIN_OS == .Darwin {
        return ctrl || gfx.key_down(.LEFT_SUPER) || gfx.key_down(.RIGHT_SUPER)
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
    fmt.printf("[probe] %-14s fullscreen=%v gfx_fullscreen=%v screen=%dx%d render=%dx%d dpi=%.2f resized=%v\n",
        tag, g_fullscreen, gfx.window_is_fullscreen(), gfx.screen_width(), gfx.screen_height(),
        gfx.render_width(), gfx.render_height(), gfx.dpi_scale(), gfx.window_resized())
}

@(private = "file")
_probe_shot :: proc(tag: string) {
    path := strings.clone_to_cstring(fmt.tprintf("%s/%s.png", g_window_probe_dir, tag), context.temp_allocator)
    gfx.screenshot(path)
}

g_tools_probe: bool

tools_probe_tick :: proc(f: int) -> (done: bool) {
    switch f {
    case 1:
        // Synthetic input for the whole run: no frame depends on the real cursor, clicks or keys.
        // Windowed too, so shots are the same size on any monitor.
        platform_set_fullscreen(false)
        gfx.set_synthetic_pointer({ f32(gfx.screen_width() / 2), f32(gfx.screen_height() / 2) })
    case 3:   _probe_shot("t00_menu")  // main menu: Clay layout and the arrow glyph
    case 5:   probe_start_singleplayer()

    // Lit gameplay, then the Clay panels: each renders into its own cached target and composites.
    case 35:  _probe_shot("t0_hub")
    case 36:  ui_open(.Inventory)
    case 50:  _probe_shot("t0b_inventory")
    case 51:
        ui_close_top()
        ui_open(.PauseMenu)
    case 65:  _probe_shot("t0c_pause")
    case 66:
        ui_close_top()
        ui_open(.Settings)
    case 80:  _probe_shot("t0d_settings")
    case 81:  ui_close_top()

    // Editor: placement, gizmo, brushes, dev tools.
    case 90:  editor_toggle()
    case 140: _probe_shot("t1_editor")
    case 141:
        for d, i in g_entity_defs { if d.name == "enemy_brute" { g_ed_def_idx = i } }
        ed_entity_place({ 160, 96 })
        g_ed_tool = .Select
    case 150:
        h := ed_gizmo_probe_handle()
        gfx.set_synthetic_pointer(h)
    case 179: fmt.printf("[probe] selected=%d entities=%d tool=%v hover=%v\n", g_ed_sel_entity, len(g_level_data.entities), g_ed_tool, ed_gizmo_hover())
    case 180: _probe_shot("t2_inspector")
    case 181: ed_gizmo_probe_drag(128, 64)
    case 190: _probe_shot("t2b_gizmo_drag")
    case 191:
        ed_gizmo_cancel()
        g_ed_tool       = .Paint
        g_ed_brush      = .HubCollision
        g_ed_brush_size = g_ed_cell_size * 4
        gfx.set_synthetic_pointer({ f32(gfx.screen_width() / 2), f32(gfx.screen_height() / 2 + 60) })
    case 200:
        c := ed_mouse_cell()
        ed_stroke_begin(.Paint, .LEFT)
        ed_stroke_update({ c[0] - 12, c[1] - 2 })
        ed_stroke_update(c)
    case 215: _probe_shot("t2c_brush_stroke")
    case 216:
        ed_stroke_end()
        g_ed_tool = .Erase
    case 225: _probe_shot("t2d_erase_cursor")
    case 226:
        g_ed_tool = .Select
        console_set_open(true)
        console_log("> help")
        console_log("probe: console line")
        g_light_widget_open = true
        dbg_inspector_toggle()
    case 250: _probe_shot("t3_tools")
    case 251:
        console_set_open(false)
        g_light_widget_open = false
        g_dbg_insp_open     = false
        editor_toggle()
        anim_editor_open_sprite("player_sheriff")
    case 310: _probe_shot("t4_anim_editor")
    case 311:
        anim_editor_close()
        enter_raid(&g_sim.world, 1)
    case 340: editor_toggle()
    case 370:
        g_ed_tool       = .Paint
        g_ed_brush      = .Oil
        g_ed_brush_size = TILE_SIZE * 3
        gfx.set_synthetic_pointer({ f32(gfx.screen_width() / 2), f32(gfx.screen_height() / 2) })
    case 400: _probe_shot("t5_raid_brush")
    case 401: return true
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
    case 3:   _probe_shot("t00_menu")  // main menu: Clay layout and the arrow glyph
    case 5:   probe_start_singleplayer()
    case 90:  _probe_log("startup");    _probe_shot("1_startup")
    case 91:  platform_set_fullscreen(false)
    case 180: _probe_log("windowed");   _probe_shot("2_windowed")
    case 181: platform_set_fullscreen(true)
    case 270: _probe_log("fullscreen"); _probe_shot("3_fullscreen")
    case 271: platform_set_fullscreen(false)
    case 350: _probe_log("restored");   _probe_shot("4_restored")
    case 351: return true
    }
    return false
}
