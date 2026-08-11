package main

import rl       "vendor:raylib"
import cw       "clockwork"
import p2p      "p2p"
import "core:os"
import "core:path/filepath"

SCREEN_WIDTH  :: 1920
SCREEN_HEIGHT :: 1080
MOVE_SPEED    :: 240.0
CAMERA_ZOOM   :: 1.0
TILE_SIZE     :: 64
PLAYER_RADIUS :: 16.0

TICK_RATE :: 60
TICK_DT   :: f32(1.0 / TICK_RATE)
// Max simulation ticks caught up in a single frame; beyond this we drop the backlog
// so one long frame can't cascade into an ever-growing catch-up (spiral of death).
MAX_CATCHUP_TICKS :: 5

g_camera:            ^rl.Camera2D

g_session:    p2p.Session
g_local_hist: p2p.HistoryBuf
g_stall_acc:  f32

g_sim:        cw.Simulation
g_sim_alive:  bool
g_accumulator: f64

g_was_player_alive: bool = true

@(private)
do_sim_tick :: proc(sim: ^cw.Simulation, local_frame: p2p.InputFrame, dt: f32) -> (ran: bool) {
    result := p2p.lockstep_advance(&g_session, local_frame, &g_local_hist, &g_stall_acc, dt)
    switch result {
    case .Offline:
        g_staged_input[sim.world.local_player_slot] = local_frame
        cw.sim_tick(sim, dt)
        return true
    case .Ready:
        lf, rf := p2p.lockstep_consume(&g_session)
        g_staged_input[g_session.local_slot]     = lf
        g_staged_input[1 - g_session.local_slot] = rf
        cw.sim_tick(sim, dt)
        return true
    case .Stalled:
        return false
    }
    return false
}

// Accept a pending co-op invitation from whatever state the player is in.
accept_invite :: proc() {
    if !g_invite_pending { return }
    if p2p.session_is_online(&g_session) { g_invite_pending = false; return }

    // Already in a hub: connect in place (the proven path).
    if g_app_state == .Playing && g_playing_state == .Hub {
        g_is_host = false
        copy(g_session.local_name[:], g_player_name[:])
        p2p.session_join(&g_session, g_invite_host_id)
        g_invite_pending = false
        return
    }

    // Otherwise load into a hub as a client first — which needs a chosen character.
    if g_active_slot < 0 { return }   // prompt hints to pick a character
    fade_to_black(_on_black_join_invite)
}

draw_invite_toast :: proc() {
    if !g_invite_pending || p2p.session_is_online(&g_session) { return }

    sw := f32(rl.GetScreenWidth())
    pw := uis(380)
    ph := uis(60)
    px := sw * 0.5 - pw * 0.5
    py := uis(16)

    rl.DrawRectangleRec({ px, py, pw, ph }, rl.Color{ 10, 8, 6, 240 })
    rl.DrawRectangleLinesEx({ px, py, pw, ph }, 1.5, COL_BRASS)
    rl.DrawRectangle(i32(px), i32(py), i32(pw), i32(uis(3)), COL_BRASS)

    buf: [96]u8
    n := copy(buf[:], g_invite_host_name[:g_invite_name_len])
    n += copy(buf[n:], " invites you to co-op")
    buf[n] = 0
    title := cstring(&buf[0])
    tfs   := uis(13)
    tsz   := rl.MeasureTextEx(g_font_body, title, tfs, 0.5)
    rl.DrawTextEx(g_font_body, title, { px + pw*0.5 - tsz.x*0.5, py + uis(11) }, tfs, 0.5, COL_PARCH)

    can_join := (g_app_state == .Playing && g_playing_state == .Hub) || g_active_slot >= 0
    hint := cstring("[J] Join      [N] Dismiss") if can_join else cstring("Select a character to join      [N] Dismiss")
    hfs  := uis(11)
    hsz  := rl.MeasureTextEx(g_font_body, hint, hfs, 0.5)
    rl.DrawTextEx(g_font_body, hint, { px + pw*0.5 - hsz.x*0.5, py + ph - uis(20) }, hfs, 0.5, COL_BRASS)
}

init_game :: proc() {
    g_sim       = cw.make_default_simulation()
    g_sim_alive = true

    g_player_names = {}
    copy(g_player_names[g_session.local_slot][:], g_player_name[:])
    if p2p.session_is_online(&g_session) {
        remote_slot := 1 - g_session.local_slot
        copy(g_player_names[remote_slot][:], g_session.remote_name[:])
    }

    cw.sim_register_system(&g_sim, { .EarlyUpdate }, stats_system)
    cw.sim_register_system(&g_sim, { .EarlyUpdate }, player_input_system)
    cw.sim_register_system(&g_sim, { .EarlyUpdate }, dodge_system)
    cw.sim_register_system(&g_sim, { .Update      }, animation_system)
    cw.sim_register_system(&g_sim, { .Update      }, facing_system)
    cw.sim_register_system(&g_sim, { .Update      }, weapon_system)


    cw.sim_register_system(&g_sim, { .EarlyUpdate, .Update, .LateUpdate }, stealth_system)
    cw.sim_register_system(&g_sim, { .Update      }, ai_system)
    cw.sim_register_system(&g_sim, { .Update      }, spawn_director_system)
    cw.sim_register_system(&g_sim, { .EarlyUpdate, .Update }, mutation_effects_system)
    cw.sim_register_system(&g_sim, { .Update      }, reanimated_system)
    cw.sim_register_system(&g_sim, { .Update      }, ability_system)
    cw.sim_register_system(&g_sim, { .Update      }, flask_system)
    cw.sim_register_system(&g_sim, { .Update      }, homing_system)
    cw.sim_register_system(&g_sim, { .Update      }, trap_system)
    cw.sim_register_system(&g_sim, { .Update      }, grenade_system)
    cw.sim_register_system(&g_sim, { .Update      }, extraction_system)
    cw.sim_register_system(&g_sim, { .Update      }, melee_arc_system)
    cw.sim_register_system(&g_sim, { .Update      }, projectile_collision_system)
    cw.sim_register_system(&g_sim, { .Update      }, pickup_system)
    cw.sim_register_system(&g_sim, { .Update      }, status_effect_system)
    cw.sim_register_system(&g_sim, { .Update      }, fire_patch_system)
    cw.sim_register_system(&g_sim, { .Update      }, env_interaction_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, damage_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, barrel_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, env_container_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, camera_follow_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, entity_separation_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, wall_collision_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, projectile_wall_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, level_exit_system)

    w := &g_sim.world

    g_sim.state = .Running

    w.local_player_slot = g_session.local_slot

    fire_system_init()
    door_blockers_init()

    g_available_levels = level_scan_available()
    level_load(0)
    level_apply(w)
    door_init_blockers(w)
    hub_apply(w)
    spawn_players(w)
    g_stash[0] = stash_make_empty()
    g_stash[1] = stash_make_empty()
    if !load_player(w, w.player_id) {
        give_class_starter_items(w, w.player_id, class_idx_for_slot(g_active_slot))
    }
    hub_apply_quest_npcs(w)

    if cw.world_has_component(&g_sim.world, g_sim.world.player_id, .Health) {
        h := cw.world_get_health(&g_sim.world, g_sim.world.player_id)
        h.current = h.max
    }

    play_music("main_theme")
    play_ambience("wind")

    g_accumulator = 0
}

shutdown_game :: proc() {
    if g_sim_alive {
        w := &g_sim.world
        if cw.world_is_valid(w, w.player_id) &&
           g_playing_state != .DeathScreen {
            save_player(w, w.player_id)
        }
    }

    hub_unload_bg()
    stop_music()
    stop_ambience()

    if g_sim_alive {
        fire_system_destroy()
        door_blockers_destroy()
        cw.destroy_simulation(&g_sim)
        g_sim_alive = false
    }

    p2p.session_shutdown(&g_session)
    g_local_hist = {}
    g_stall_acc  = 0
    g_accumulator = 0

    ui_close_all()

    set_playing_state(.Gameplay)
    g_pending_level_switch = 0
    g_raid_timer           = 0
    g_is_host              = false
    g_stash[0]             = stash_make_empty()
    g_stash[1]             = stash_make_empty()
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
        sw       := f32(rl.GetScreenWidth())
        sh       := f32(rl.GetScreenHeight())
        inv_open := ui_has(.Inventory) || ui_has(.Shop) || ui_has(.Stash)
        if inv_open {
            g_camera.offset = { (sw - f32(g_inv.panel_w)) * 0.5, sh * 0.5 }
        } else {
            g_camera.offset = { sw * 0.5, sh * 0.5 }
        }
    }
    if !g_editor_mode {
        g_camera.zoom = f32(rl.GetScreenHeight()) / 720.0
    }

    if !g_sim_alive { return }
    w := &g_sim.world

    // After handshake: send our character data to the peer once.
    if g_session.peer_ready && !g_session.char_data_sent && cw.world_is_valid(w, w.player_id) {
        bytes := player_to_bytes(w, w.player_id)
        p2p.session_send_char_data(&g_session, bytes)
        g_session.char_data_sent = true
    }

    minimap_update(w)

    if cw.world_is_valid(w, w.player_id) &&
       cw.world_has_component(w, w.player_id, .Transform) {
        set_audio_listener(cw.world_get_transform(w, w.player_id).position)
    }

    if input_pressed(.F1) && g_is_host && !g_console_open && !g_anim_ed.open &&
       (g_playing_state == .Editor || g_playing_state == .Gameplay || g_playing_state == .Hub) {
        editor_toggle()
    }
    if input_pressed(.F3) && g_is_host && !g_console_open &&
       (g_playing_state == .Editor || g_playing_state == .Gameplay || g_playing_state == .Hub) {
        if g_anim_ed.open { anim_editor_close() } else { anim_editor_open() }
    }
    update_lighting_widget()

    if !g_console_open && !g_anim_ed.open {

        switch g_playing_state {

        case .Editor:
            update_editor(dt)

        case .Hub:

            // Client: pick up level-load notification sent by the host.
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

            // Mid-hub join: spawn remote player once char data arrives.
            if p2p.session_is_online(&g_session) {
                remote_slot := 1 - g_session.local_slot
                if !g_hub_remote_spawned {
                    if g_session.remote_char_ready {
                        hub_spawn_remote_player(w)
                        g_hub_remote_spawned = true
                        g_hub_remote_loaded  = true
                    }
                } else if !g_hub_remote_loaded && g_session.remote_char_ready {
                    if cw.world_is_valid(w, w.player_ids[remote_slot]) {
                        load_player_from_bytes(w, w.player_ids[remote_slot],
                            g_session.remote_char_data[:g_session.remote_char_len])
                        g_hub_remote_loaded = true
                    }
                }
            }

            if input_is_gameplay() {
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.pause)) {
                    ui_open(.PauseMenu)
                }
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.open_inventory)) {
                    ui_open(.Inventory)
                }
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.open_stats)) {
                    ui_open(.Stats)
                }
                if rl.IsKeyPressed(.O) {
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
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.pause)) {
                    ui_open(.PauseMenu)
                }
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.open_inventory)) {
                    ui_open(.Inventory)
                }
                if input_pressed(rl.KeyboardKey(g_binds.gameplay.open_stats)) {
                    ui_open(.Stats)
                }
                update_mutation_workbench(w)
                update_shop(w)
                update_stash(w)
                update_ability_vendor(w)

                if input_pressed(rl.KeyboardKey(g_binds.gameplay.loot_filter)) {
                    switch g_loot_filter_rarity {
                    case .Normal:    g_loot_filter_rarity = .Rare
                    case .Rare:      g_loot_filter_rarity = .Epic
                    case .Epic:      g_loot_filter_rarity = .Legendary
                    case .Legendary: g_loot_filter_rarity = .Normal
                    case .Unique:    g_loot_filter_rarity = .Normal
                    }
                }
            }

        case .ExtractScreen, .DeathScreen:


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

    if g_playing_state != .DeathScreen && g_playing_state != .ExtractScreen {
        local_frame := collect_local_input() if playing_collects_input() else p2p.InputFrame{}
        g_accumulator += f64(dt)
        n := 0
        for g_accumulator >= f64(TICK_DT) {
            do_sim_tick(&g_sim, local_frame, TICK_DT)
            g_accumulator -= f64(TICK_DT)
            local_frame.actions = {}
            n += 1
            if n >= MAX_CATCHUP_TICKS {
                g_accumulator = 0   // drop the backlog rather than spiral on a bad frame
                break
            }
        }
    }


    if g_playing_state == .Gameplay &&
       cw.world_is_valid(w, w.player_id) &&
       cw.world_has_component(w, w.player_id, .Respawn) {
        rsp          := cw.world_get_respawn(w, w.player_id)
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
}

@(private)
draw_playing :: proc() {
    if !g_sim_alive { return }
    w := &g_sim.world

    ensure_lighting_render_targets()
    draw_directional_shadow_mask(w)

    rl.BeginTextureMode(g_world_rt)
    rl.ClearBackground(rl.BLANK)
    rl.BeginMode2D(g_camera^)
    if g_hub_active {
        draw_hub_background()   // pre-rendered town image replaces tilemap in hub (editor too)
    } else if len(g_level_data.modules) > 0 {
        draw_level_modules()    // prerendered modules; tiles are invisible collision (hub model)
    } else {
        draw_tilemap()
    }
    draw_player_contact_shadow(w)
    if g_playing_state == .Hub {
        draw_hub_world(w)
    }
    draw_editor_world()
    draw_entities(w, .WorldFX)
    draw_extraction_zones(w)
    draw_shop_world(w)
    rl.EndMode2D()
    rl.EndTextureMode()

    draw_directional_world_composite()

    rl.BeginMode2D(g_camera^)
    draw_entity_sprite_shadows(w)
    rl.EndMode2D()

    rl.BeginTextureMode(g_sprite_rt)
    rl.ClearBackground(rl.BLANK)
    rl.BeginMode2D(g_camera^)
    draw_entities(w, .Sprite)
    rl.EndMode2D()
    rl.EndTextureMode()

    draw_directional_sprite_composite(w)

    draw_cloud_shadow_field()
    draw_world_god_rays()
    if !g_editor_mode { draw_fog_and_lights(w) }

    rl.BeginMode2D(g_camera^)
    draw_editor_cell_overlay()
    draw_mutation_workbench_world(w)
    draw_stash_world(w)
    draw_ability_vendor_world(w)
    draw_quest_board_world(w)
    draw_enemy_mutation_auras(w)
    draw_water_puddles()
    draw_fire_patches()
    draw_barrels()
    draw_status_effects(w)
    draw_ground_item_labels(w)
    draw_explosions()
    draw_grenades_and_clouds(w)
    draw_traps(w)
    update_draw_dmg_numbers(rl.GetFrameTime())
    if !g_editor_mode { draw_stealth_indicators(w) }
    rl.EndMode2D()

    draw_editor_hud()
    if !g_editor_mode {
        update_entity_hover(w)
        draw_boss_warning()
        draw_entity_inspect_hud(w)
        draw_raid_timer()
        draw_hud(w)


        if g_playing_state == .Hub {
            draw_hub_hud(w)
        }


        switch g_playing_state {
        case .ExtractScreen:
            draw_extract_screen(w)
        case .DeathScreen:
            draw_death_screen(w)
        case .Gameplay, .Hub, .Editor:

        }

        draw_minimap(w)
        draw_levelup_flash()
        draw_quest_flash()
        draw_quest_hud(w)
        draw_loot_filter_hud()
    }


    draw_lighting_widget()
}


main :: proc() {
    if len(os.args) > 0 {
        exe_dir := filepath.dir(os.args[0], context.temp_allocator)
        if filepath.base(exe_dir) == "bin" {
            os.set_current_directory(filepath.dir(exe_dir, context.temp_allocator))
        } else {
            os.set_current_directory(exe_dir)
        }
    }

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tormentas")
    defer rl.CloseWindow()
    app_icon := rl.LoadImage("data/app/tormentas_icon.png")
    if app_icon.data != nil {
        rl.SetWindowIcon(app_icon)
        rl.UnloadImage(app_icon)
    }
    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    load_config()
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

    init_cloud_shader()
    defer shutdown_cloud_shader()

    init_godray_shader()
    defer shutdown_godray_shader()

    init_directional_shader()
    defer shutdown_directional_shader()

    init_foglight_shader()
    defer shutdown_foglight_shader()

    init_wall_mask()
    defer shutdown_wall_mask()

    init_pause_menu()

    camera := rl.Camera2D{
        offset   = { SCREEN_WIDTH / 2.0, SCREEN_HEIGHT / 2.0 },
        target   = { 0, 0 },
        rotation = 0,
        zoom     = CAMERA_ZOOM,
    }
    g_camera = &camera

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

    chars_load_all()
    _mm_init()

    steam_init()
    defer steam_shutdown()

    for !rl.WindowShouldClose() && !g_should_exit {
        dt := rl.GetFrameTime()
        defer free_all(context.temp_allocator)

        steam_run_callbacks()

        // Once we've entered the invited lobby, resolve its host into a pending co-op
        // invitation the player can accept from anywhere via the on-screen prompt.
        // Retried each frame — lobby data can lag a frame behind LobbyEnter.
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

        // Invite prompt input (guarded against console / name-entry text capture).
        if g_invite_pending && !p2p.session_is_online(&g_session) {
            typing := g_console_open || (g_app_state == .MainMenu && g_mm.focus == .NewName)
            if !typing {
                if rl.IsKeyPressed(.J) { accept_invite() }
                if rl.IsKeyPressed(.N) { g_invite_pending = false }
            }
        }

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


        if ui_any() && input_pressed(rl.KeyboardKey(g_binds.ui.close_panel)) {
            ui_close_top()
        }
        ui_update(dt)

        rl.BeginDrawing()
        rl.ClearBackground({10, 10, 14, 255})

        switch g_app_state {
        case .MainMenu:
            draw_main_menu()
        case .Connecting:
            draw_connecting()
        case .Playing:
            draw_playing()
        }


        {
            ui_w := (^cw.World)(nil)
            if g_app_state == .Playing && g_sim_alive {
                ui_w = &g_sim.world
            }
            ui_draw(ui_w)
        }

        draw_invite_toast()
        draw_anim_editor()
        draw_fade()
        draw_console()
        rl.EndDrawing()
    }

    if g_sim_alive { shutdown_game() }
}
