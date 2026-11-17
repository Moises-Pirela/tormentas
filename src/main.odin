package main

import gfx      "gfx"
import p2p      "p2p"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:time"

SCREEN_WIDTH  :: 1920
SCREEN_HEIGHT :: 1080
MOVE_SPEED    :: 240.0
CAMERA_ZOOM   :: 1.0
TILE_SIZE     :: 64
PLAYER_RADIUS :: 16.0

TICK_RATE :: 60
TICK_DT   :: f32(1.0 / TICK_RATE)

MAX_CATCHUP_TICKS :: 5


g_session:    p2p.Session

g_sim:        Simulation
g_sim_alive:  bool
g_accumulator: f64

g_was_player_alive: bool = true

do_sim_tick :: proc(local_frame: p2p.InputFrame, dt: f32) {
    if p2p.session_is_online(&g_session) && g_session.local_slot != 0 {
        netcode_client_tick(local_frame, dt)
    } else {
        netcode_host_tick(local_frame, dt)
    }
}

LOOPBACK_PORT :: 27600

boot_loopback_from_args :: proc() {
    args := os.args
    if len(args) < 2 { return }
    mode := args[1]
    if mode != "hostlocal" && mode != "joinlocal" { return }

    port := u16(LOOPBACK_PORT)
    if len(args) >= 3 {
        if v, ok := strconv.parse_int(args[2]); ok {
            port = u16(v)
        }
    }

    if mode == "hostlocal" {
        _boot_hostlocal(port)
    } else {
        _boot_joinlocal(port)
    }
}

LOOPBACK_CONNECT_TIMEOUT :: f32(15.0)

@(private = "file")
_boot_wait_for_connection :: proc() -> bool {
    timer := f32(0)
    for timer < LOOPBACK_CONNECT_TIMEOUT {
        steam_run_callbacks()
        p2p.session_poll(&g_session, 1.0 / 60.0)
        if p2p.session_is_online(&g_session) { return true }
        if p2p.session_is_disconnected(&g_session) { return false }
        time.sleep(time.Millisecond * 16)
        timer += 1.0 / 60.0
    }
    return false
}

@(private = "file")
_boot_hostlocal :: proc(port: u16) {
    g_is_host = true
    copy(g_player_name[:], "Host")
    copy(g_session.local_name[:], g_player_name[:])
    if !p2p.session_host_loopback(&g_session, port) { return }
    if !_boot_wait_for_connection() {
        fmt.eprintln("[loopback] timed out waiting for joinlocal peer")
        p2p.session_shutdown(&g_session)
        return
    }
    init_game()
    g_hub_active = true
    g_app_state  = .Playing
    set_playing_state(.Hub)
}

@(private = "file")
_boot_joinlocal :: proc(port: u16) {
    g_is_host = false
    copy(g_player_name[:], "Client")
    copy(g_session.local_name[:], g_player_name[:])
    if !p2p.session_join_loopback(&g_session, port) { return }
    if !_boot_wait_for_connection() {
        fmt.eprintln("[loopback] timed out waiting for hostlocal peer")
        p2p.session_shutdown(&g_session)
        return
    }
    init_game()
    g_hub_active = true
    g_app_state  = .Playing
    set_playing_state(.Hub)
}

accept_invite :: proc() {
    if !g_invite_pending { return }
    if p2p.session_is_online(&g_session) { g_invite_pending = false; return }

    if g_app_state == .Playing && g_playing_state == .Hub {
        g_is_host = false
        copy(g_session.local_name[:], g_player_name[:])
        p2p.session_join(&g_session, g_invite_host_id)
        g_invite_pending = false
        return
    }

    if g_active_slot < 0 { return }
    fade_to_black(_on_black_join_invite)
}

draw_invite_toast :: proc() {
    if !g_invite_pending || p2p.session_is_online(&g_session) { return }

    sw := f32(gfx.screen_width())
    pw := uis(380)
    ph := uis(60)
    px := sw * 0.5 - pw * 0.5
    py := uis(16)

    gfx.draw_rect_rec({ px, py, pw, ph }, gfx.Color{ 10, 8, 6, 240 })
    gfx.draw_rect_lines({ px, py, pw, ph }, 1.5, COL_BRASS)
    gfx.draw_rect(i32(px), i32(py), i32(pw), i32(uis(3)), COL_BRASS)

    buf: [96]u8
    n := copy(buf[:], g_invite_host_name[:g_invite_name_len])
    n += copy(buf[n:], " invites you to co-op")
    buf[n] = 0
    title := cstring(&buf[0])
    tfs   := uis(13)
    tsz   := gfx.measure_text(g_font_body, title, tfs, 0.5)
    gfx.draw_text(g_font_body, title, { px + pw*0.5 - tsz.x*0.5, py + uis(11) }, tfs, 0.5, COL_PARCH)

    can_join := (g_app_state == .Playing && g_playing_state == .Hub) || g_active_slot >= 0
    hint := cstring("[J] Join      [N] Dismiss") if can_join else cstring("Select a character to join      [N] Dismiss")
    hfs  := uis(11)
    hsz  := gfx.measure_text(g_font_body, hint, hfs, 0.5)
    gfx.draw_text(g_font_body, hint, { px + pw*0.5 - hsz.x*0.5, py + ph - uis(20) }, hfs, 0.5, COL_BRASS)
}

init_game :: proc() {
    g_sim       = make_default_simulation()
    g_sim_alive = true

    g_player_names = {}
    copy(g_player_names[g_session.local_slot][:], g_player_name[:])
    if p2p.session_is_online(&g_session) {
        for slot in 0..<MAX_PLAYERS {
            if slot == g_session.local_slot { continue }
            entry := &g_session.roster[slot]
            if entry.known { copy(g_player_names[slot][:], entry.name[:]) }
        }
    }

    sim_register_system(&g_sim, { .EarlyUpdate }, stats_system,        .Shared)
    sim_register_system(&g_sim, { .EarlyUpdate }, player_input_system, .Shared)
    sim_register_system(&g_sim, { .EarlyUpdate }, dodge_system,        .Shared)
    sim_register_system(&g_sim, { .Update      }, animation_system,    .Shared)
    sim_register_system(&g_sim, { .Update      }, facing_system,       .Shared)
    sim_register_system(&g_sim, { .Update      }, weapon_system,       .HostOnly)

    sim_register_system(&g_sim, { .EarlyUpdate, .Update, .LateUpdate }, stealth_system, .HostOnly)
    sim_register_system(&g_sim, { .Update      }, ai_system,                  .HostOnly)
    sim_register_system(&g_sim, { .Update      }, spawn_director_system,      .HostOnly)
    sim_register_system(&g_sim, { .EarlyUpdate, .Update }, mutation_effects_system, .HostOnly)
    sim_register_system(&g_sim, { .Update      }, reanimated_system,          .HostOnly)
    sim_register_system(&g_sim, { .Update      }, ability_system,             .HostOnly)
    sim_register_system(&g_sim, { .Update      }, ability_echo_system,        .Shared)
    sim_register_system(&g_sim, { .Update      }, flask_system,               .HostOnly)
    sim_register_system(&g_sim, { .Update      }, homing_system,              .HostOnly)
    sim_register_system(&g_sim, { .Update      }, trap_system,                .HostOnly)
    sim_register_system(&g_sim, { .Update      }, grenade_system,             .HostOnly)
    sim_register_system(&g_sim, { .Update      }, dungeon_clock_system,       .HostOnly)
    sim_register_system(&g_sim, { .Update      }, melee_arc_system,           .HostOnly)
    sim_register_system(&g_sim, { .Update      }, projectile_collision_system, .HostOnly)
    sim_register_system(&g_sim, { .Update      }, pickup_system,              .HostOnly)
    sim_register_system(&g_sim, { .Update      }, status_effect_system,       .HostOnly)
    sim_register_system(&g_sim, { .Update      }, fire_patch_system,          .HostOnly)
    sim_register_system(&g_sim, { .Update      }, env_interaction_system,     .HostOnly)
    sim_register_system(&g_sim, { .Update      }, env_interaction_focus_system, .Shared)
    sim_register_system(&g_sim, { .LateUpdate  }, damage_system,              .HostOnly)
    sim_register_system(&g_sim, { .LateUpdate  }, barrel_system,              .HostOnly)
    sim_register_system(&g_sim, { .LateUpdate  }, env_container_system,       .HostOnly)
    sim_register_system(&g_sim, { .LateUpdate  }, camera_follow_system,       .Shared)
    sim_register_system(&g_sim, { .LateUpdate  }, entity_separation_system,   .Shared)
    sim_register_system(&g_sim, { .LateUpdate  }, wall_collision_system,      .Shared)
    sim_register_system(&g_sim, { .LateUpdate  }, greybox_collision_system,   .Shared)
    sim_register_system(&g_sim, { .LateUpdate  }, projectile_wall_system,     .HostOnly)

    w := &g_sim.world

    g_sim.state = .Running

    w.local_player_slot = g_session.local_slot

    switch {
    case !p2p.session_is_online(&g_session): g_sim.role = .Standalone
    case g_session.local_slot != 0:          g_sim.role = .Client
    case:                                    g_sim.role = .Host
    }

    fire_system_init()
    door_blockers_init()

    g_available_levels = level_scan_available()
    level_load(0)
    level_apply(w)
    door_init_blockers(w)
    hub_apply(w)
    spawn_players(w)
    for i in 0..<MAX_PLAYERS { g_stash[i] = stash_make_empty() }
    if !load_player(w, w.player_id) {
        give_class_starter_items(w, w.player_id, class_idx_for_slot(g_active_slot))
    }
    hub_apply_quest_npcs(w)

    if world_has_component(&g_sim.world, g_sim.world.player_id, .Health) {
        h := comp_get(&g_sim.world, g_sim.world.player_id, .Health, HealthComp)
        h.current = h.max
    }

    play_music("main_theme")
    play_ambience("wind")
    play_ambience_bed("ambience_industrial")

    g_accumulator = 0
}

shutdown_game :: proc() {
    if g_sim_alive {
        w := &g_sim.world
        if world_is_valid(w, w.player_id) &&
           g_playing_state != .DeathScreen {
            save_player(w, w.player_id)
        }
    }

    hub_unload_bg()
    stop_music()
    stop_ambience()

    netcode_predictor_shutdown()
    if g_sim_alive {
        fire_system_destroy()
        door_blockers_destroy()
        destroy_simulation(&g_sim)
        g_sim_alive = false
    }

    p2p.session_shutdown(&g_session)
    g_accumulator = 0

    ui_close_all()

    set_playing_state(.Gameplay)
    g_pending_level_switch = 0
    g_raid_timer           = 0
    g_is_host              = false
    for i in 0..<MAX_PLAYERS { g_stash[i] = stash_make_empty() }
    g_active_slot          = -1
    g_lifetime_stats       = {}
}

@(private)
update_playing :: proc(dt: f32) {
    if p2p.session_is_disconnected(&g_session) {
        g_disconnect_msg_timer = DISCONNECT_MSG_DURATION
        fade_to_black(_on_black_to_menu)
        return
    }
    p2p.session_poll(&g_session, dt)

    {
        sw       := f32(gfx.screen_width())
        sh       := f32(gfx.screen_height())
        inv_open := ui_has(.Inventory) || ui_has(.Shop) || ui_has(.Stash)
        if inv_open {
            cam_set_offset({ (sw - f32(g_inv.panel_w)) * 0.5, sh * 0.5 })
        } else {
            cam_set_offset({ sw * 0.5, sh * 0.5 })
        }
    }
    if !g_editor_mode {
        cam_set_zoom(f32(gfx.screen_height()) / 1080.0)
    }

    if !g_sim_alive { return }
    w := &g_sim.world

    if world_is_valid(w, w.player_id) {
        if p2p.is_host(&g_session) {
            for &p in g_session.peers {
                if p.active && p.peer_ready && !p.char_data_sent {
                    bytes := player_to_bytes(w, w.player_id)
                    p2p.session_send_char_data_to_peer(&p, bytes)
                    p.char_data_sent = true
                }
            }
        } else if g_session.peer_ready && !g_session.char_data_sent {
            bytes := player_to_bytes(w, w.player_id)
            p2p.session_send_char_data(&g_session, bytes)
            g_session.char_data_sent = true
        }
    }

    netcode_apply_raid_result(w)
    netcode_apply_disconnects(w)
    netcode_apply_entity_syncs(w)

    if world_is_valid(w, w.player_id) &&
       world_has_component(w, w.player_id, .Transform) {
        set_audio_listener(comp_get(w, w.player_id, .Transform, TransformComp).position)
    }

    typing := devui_wants_text()
    if input_pressed(.F1) && g_is_host && !typing && !g_anim_ed.open &&
       (g_playing_state == .Editor || g_playing_state == .Gameplay || g_playing_state == .Hub) {
        editor_toggle()
    }
    if input_pressed(.F3) && g_is_host && !typing &&
       (g_playing_state == .Editor || g_playing_state == .Gameplay || g_playing_state == .Hub) {
        if g_anim_ed.open { anim_editor_close() } else { anim_editor_open() }
    }
    if input_pressed(.F6) && !typing && !g_anim_ed.open {
        dbg_inspector_toggle()
    }
    if input_pressed(.F5) && g_editor_mode && !typing {
        ed_set_mode(g_ed_mode == .Edit ? EditorMode.Live : EditorMode.Edit)
    }
    update_lighting_widget()

    if !g_anim_ed.open {
        switch g_playing_state {
        case .Editor:
            update_editor(dt)

        case .Hub:

            if g_session.pending_level_load > 0 && g_session.local_slot != 0 {
                n := g_session.pending_level_load
                g_session.pending_level_load = 0
                g_pending_raid_start = n
            }

            if g_pending_raid_start > 0 {
                n := g_pending_raid_start
                g_pending_raid_start = 0
                enter_raid(w, n)
                break
            }

            if p2p.session_is_online(&g_session) {
                for slot in 0..<MAX_PLAYERS {
                    if slot == g_session.local_slot { continue }
                    entry := &g_session.roster[slot]
                    if !entry.known { continue }

                    if !world_is_valid(w, w.player_ids[slot]) {
                        if !entry.char_ready { continue }
                        hub_spawn_remote_player(w, slot)
                        g_hub_remote_loaded[slot] = true
                        continue
                    }

                    if !g_hub_remote_loaded[slot] && entry.char_ready {
                        load_player_from_bytes(w, w.player_ids[slot], entry.char_data[:entry.char_len])
                        g_hub_remote_loaded[slot] = true
                    }
                }
            }

            if input_is_gameplay() {
                if input_pressed(gfx.Key(g_binds.gameplay.pause)) {
                    ui_open(.PauseMenu)
                }
                if input_pressed(gfx.Key(g_binds.gameplay.open_inventory)) {
                    ui_open(.Inventory)
                }
                if input_pressed(gfx.Key(g_binds.gameplay.open_stats)) {
                    ui_open(.Stats)
                }
                if gfx.key_pressed(.O) {
                    if ui_has(.Social) { ui_close(.Social) } else { ui_open(.Social) }
                }
                update_mutation_workbench(w)
                update_shop(w)
                update_stash(w)
                update_ability_vendor(w)
                update_quest_board(w)
                update_hub_portal(w)
            }

        case .Gameplay:
            if input_is_gameplay() {
                if input_pressed(gfx.Key(g_binds.gameplay.pause)) {
                    ui_open(.PauseMenu)
                }
                if input_pressed(gfx.Key(g_binds.gameplay.open_inventory)) {
                    ui_open(.Inventory)
                }
                if input_pressed(gfx.Key(g_binds.gameplay.open_stats)) {
                    ui_open(.Stats)
                }
                update_mutation_workbench(w)
                update_shop(w)
                update_stash(w)
                update_ability_vendor(w)

                if input_pressed(gfx.Key(g_binds.gameplay.loot_filter)) {
                    switch g_loot_filter_rarity {
                    case .Normal:    g_loot_filter_rarity = .Rare
                    case .Rare:      g_loot_filter_rarity = .Epic
                    case .Epic:      g_loot_filter_rarity = .Legendary
                    case .Legendary: g_loot_filter_rarity = .Normal
                    case .Unique:    g_loot_filter_rarity = .Normal
                    }
                }
            }

        case .DeathScreen:
        }

        if input_is_ui() {
            top, ok := ui_top()
            if ok {
                switch top {
                case .PauseMenu:
                    if update_pause_menu() {
                        fade_to_black(_on_black_to_menu)
                        return
                    }
                case .Keybinds:
                    update_keybinds_screen()
                case .MutationTree:
                    update_mutation_tree(w)
                case .Shop:
                    update_shop(w)
                case .Stash:
                    update_stash(w)
                case .AbilityVendor:
                    update_ability_vendor(w)
                case .Settings, .LevelSelect, .Inventory, .Stats,
                     .Lore, .Phonograph, .Social, .QuestBoard:
                }
            }
        }
    }

    sim_paused := g_paused && !p2p.session_is_online(&g_session)
    if sim_paused || g_playing_state == .DeathScreen {
        g_accumulator = 0
        clear_pending_actions()
    }
    if !sim_paused && g_playing_state != .DeathScreen {
        local_frame := collect_local_input() if playing_collects_input() else p2p.InputFrame{}
        g_accumulator += f64(dt)
        n := 0
        for g_accumulator >= f64(TICK_DT) {
            do_sim_tick(local_frame, TICK_DT)
            g_accumulator -= f64(TICK_DT)
            local_frame.actions = {}
            clear_pending_actions()
            n += 1
            if n >= MAX_CATCHUP_TICKS {
                g_accumulator = 0
                break
            }
        }
        netcode_interp_update()
    }

    if g_playing_state == .Gameplay &&
       world_is_valid(w, w.player_id) &&
       world_has_component(w, w.player_id, .Respawn) {
        rsp          := comp_get(w, w.player_id, .Respawn, RespawnComp)
        player_alive := rsp.timer <= 0
        if !player_alive && g_was_player_alive {
            on_player_death(w)
        }
        g_was_player_alive = player_alive
    }

    g_levelup_flash = max(g_levelup_flash - dt, 0)
    if g_pending_level_switch > 0 {
        level_do_switch(w, int(g_pending_level_switch))
    }
    tick_camera_shake(dt)
    tick_explosions(dt)
    tick_hit_flashes(dt)
    tick_footsteps(w, dt)
}

@(private)
draw_playing :: proc() {
    if !g_sim_alive { return }
    w := &g_sim.world

    ensure_lighting_render_targets()
    draw_directional_shadow_mask(w)

    gfx.target_begin(g_world_rt)
    gfx.clear(gfx.BLANK)
    cam_begin()
    if g_hub_active {
        draw_hub_background()
    } else if len(g_level_data.modules) > 0 {
        draw_level_modules()
    } else {
        draw_tilemap()
    }
    if g_playing_state == .Hub {
        draw_hub_world(w)
    }
    draw_entities(w, .WorldFX)
    draw_shop_world(w)
    cam_end()
    gfx.target_end()

    draw_directional_world_composite()

    cam_begin()
    draw_entity_sprite_shadows(w)
    draw_player_projected_shadow(w)
    cam_end()

    gfx.target_begin(g_sprite_rt)
    gfx.clear(gfx.BLANK)
    cam_begin()
    draw_entities(w, .Sprite)
    cam_end()
    gfx.target_end()

    draw_directional_sprite_composite(w)

    draw_cloud_shadow_field()
    draw_world_god_rays()
    if !g_editor_mode { draw_fog_and_lights(w) }

    cam_begin()
    draw_editor_cell_overlay()
    draw_editor_world()
    draw_editor_brush_world()
    if !g_editor_mode { draw_player_aim_line(w) }
    draw_mutation_workbench_world(w)
    draw_stash_world(w)
    draw_ability_vendor_world(w)
    draw_quest_board_world(w)
    draw_enemy_mutation_auras(w)
    draw_water_puddles()
    draw_fire_patches()
    draw_barrels()
    draw_status_effects(w)
    draw_enemy_telegraphs(w)
    draw_enemy_health_bars(w, gfx.frame_time())
    draw_ground_item_labels(w)
    draw_explosions()
    draw_grenades_and_clouds(w)
    draw_traps(w)
    update_draw_dmg_numbers(gfx.frame_time())
    if !g_editor_mode { draw_stealth_indicators(w) }
    cam_end()

    if !g_editor_mode {
        update_entity_hover(w)
        draw_boss_warning()
        draw_entity_inspect_hud(w)
        draw_hud(w)

        if g_playing_state == .Hub {
            draw_hub_hud(w)
        }

        switch g_playing_state {
        case .DeathScreen:
            draw_death_screen(w)
        case .Gameplay, .Hub, .Editor:
        }

        draw_levelup_flash()
        draw_quest_flash()
        draw_quest_hud(w)
        draw_loot_filter_hud()
    }


}

main :: proc() {
    if len(os.args) > 0 {
        exe_dir := filepath.dir(os.args[0])
        if filepath.base(exe_dir) == "bin" {
            _ = os.set_working_directory(filepath.dir(exe_dir))
        } else {
            _ = os.set_working_directory(exe_dir)
        }
    }

    window_probe_from_args()
    migrate_legacy_user_files()
    load_config()
    platform_init_window("Tormentas")
    defer gfx.window_close()
    if app_icon, ok := gfx.load_image("data/app/tormentas_icon.png"); ok {
        gfx.window_set_icon(app_icon)
        gfx.unload_image(app_icon)
    }
    gfx.set_target_fps(60)

    g_lang = Language(min(g_binds.language, u8(LANG_COUNT - 1)))

    loc_init()
    defer loc_destroy()

    init_audio()
    defer shutdown_audio()

    init_clay()
    defer shutdown_clay()

    ui_init()
    defer ui_destroy()

    init_font()
    defer shutdown_font()

    init_icon_cache()
    defer shutdown_icon_cache()

    init_anim_cache()
    defer shutdown_anim_cache()

    init_fog()
    defer shutdown_fog()

    init_lighting()
    defer shutdown_lighting()

    init_wall_mask()
    defer shutdown_wall_mask()

    init_pause_menu()

    cam_init()

    tilemap_init()
    defer tilemap_destroy()

    module_registry_init()
    defer module_registry_destroy()

    ai_paths_init()
    defer ai_paths_destroy()

    level_data_init()
    defer level_data_destroy()

    if !loot_table_load("data/loot_table.csv") { return }
    defer loot_table_destroy()

    lore_db_load()

    {
        defs, ok := load_entity_defs("data/entities.json")
        if !ok { return }
        g_entity_defs = defs
    }
    defer destroy_entity_defs(g_entity_defs)

    // Needs the entity definitions, and must happen before any frame draws (see the proc).
    prebuild_entity_sprites()

    chars_load_all()
    _mm_init()

    steam_init()
    defer steam_shutdown()

    boot_loopback_from_args()

    for !gfx.window_should_close() && !g_should_exit {
        if !app_frame() { break }
    }

    platform_store_display_settings()
    save_config()

    dbg_inspector_shutdown()
    devui_shutdown()
    if g_sim_alive { shutdown_game() }
}

// One frame of the whole app: input, update, draw. The raylib loop in main calls it; under
// sokol_app (P1a step 7) it becomes the body of the frame callback, because sokol owns the loop.
app_frame :: proc() -> (keep_running: bool) {
    dt := gfx.frame_time()
    defer free_all(context.temp_allocator)

    steam_run_callbacks()
    platform_update_window()
    if window_probe_tick() { return false }

    if g_pending_join_lobby != 0 && !g_invite_pending && !p2p.session_is_online(&g_session) {
        host_id := steam_lobby_get_host_id(g_pending_join_lobby)
        if host_id != 0 && host_id != steam_get_local_id() {
            g_steam_lobby_id     = g_pending_join_lobby
            g_pending_join_lobby = 0
            g_invite_host_id     = host_id
            nm := steam_friend_name(host_id)
            g_invite_name_len = min(len(nm), len(g_invite_host_name) - 1)
            copy(g_invite_host_name[:], nm[:g_invite_name_len])
            g_invite_host_name[g_invite_name_len] = 0
            g_invite_pending = true
        }
    }

    if g_invite_pending && !p2p.session_is_online(&g_session) {
        typing := devui_wants_text() || (g_app_state == .MainMenu && g_mm.focus == .NewName)
        if !typing {
            if gfx.key_pressed(.J) { accept_invite() }
            if gfx.key_pressed(.N) { g_invite_pending = false }
        }
    }

    devui_begin_frame(dt)
    update_clay_input()
    input_begin_frame()
    update_audio()
    update_music_state(&g_sim.world)
    update_fade(dt)
    update_console(dt)
    update_anim_editor(dt)

    switch g_app_state {
    case .MainMenu:
        update_main_menu(dt)
    case .Connecting:
        update_connecting(dt)
    case .Playing:
        update_playing(dt)
    }

    if ui_any() && input_pressed(gfx.Key(g_binds.ui.close_panel)) {
        ui_close_top()
    }
    ui_update(dt)

    gfx.frame_begin()
    gfx.clear({10, 10, 14, 255})

    switch g_app_state {
    case .MainMenu:
        draw_main_menu()
    case .Connecting:
        draw_connecting()
    case .Playing:
        draw_playing()
    }

    {
        ui_w := (^World)(nil)
        if g_app_state == .Playing && g_sim_alive {
            ui_w = &g_sim.world
        }
        ui_draw(ui_w)
    }

    draw_invite_toast()
    draw_fade()
    draw_editor_overlay_screen()
    devui_tools_frame()
    devui_end_frame()
    gfx.frame_end()
    gfx.end_input_frame()
    return true
}
