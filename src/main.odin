package main

import rl       "vendor:raylib"
import cw       "clockwork"
import p2p      "p2p"
import "core:os"
import "core:path/filepath"

SCREEN_WIDTH  :: 1920
SCREEN_HEIGHT :: 1080
MOVE_SPEED    :: 150.0
CAMERA_ZOOM   :: 1.0
TILE_SIZE     :: 40
PLAYER_RADIUS :: 16.0

TICK_RATE :: 60
TICK_DT   :: f32(1.0 / TICK_RATE)

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
    cw.sim_register_system(&g_sim, { .Update      }, ai_system)
    cw.sim_register_system(&g_sim, { .Update      }, spawn_director_system)
    cw.sim_register_system(&g_sim, { .EarlyUpdate, .Update }, mutation_effects_system)
    cw.sim_register_system(&g_sim, { .Update      }, reanimated_system)
    cw.sim_register_system(&g_sim, { .Update      }, ability_system)
    cw.sim_register_system(&g_sim, { .Update      }, extraction_system)
    cw.sim_register_system(&g_sim, { .Update      }, melee_arc_system)
    cw.sim_register_system(&g_sim, { .Update      }, projectile_collision_system)
    cw.sim_register_system(&g_sim, { .Update      }, pickup_system)
    cw.sim_register_system(&g_sim, { .Update      }, status_effect_system)
    cw.sim_register_system(&g_sim, { .Update      }, fire_patch_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, damage_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, barrel_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, camera_follow_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, wall_collision_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, projectile_wall_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, level_exit_system)

    w := &g_sim.world

    g_sim.state = .Running

    w.local_player_slot = g_session.local_slot

    fire_system_init()

    level_load(0)
    level_apply(w)
    hub_apply(w)
    spawn_players(w)
    g_stash = stash_make_empty()
    load_player(w, w.player_id)

    // Full HP on first spawn-in.
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

    stop_music()
    stop_ambience()

    if g_sim_alive {
        fire_system_destroy()
        cw.destroy_simulation(&g_sim)
        g_sim_alive = false
    }

    p2p.session_shutdown(&g_session)
    g_local_hist = {}
    g_stall_acc  = 0
    g_accumulator = 0

    ui_close_all()   // clear any open UI panels instantly

    set_playing_state(.Gameplay)
    g_pending_level_switch = 0
    g_raid_timer           = 0
    g_is_host              = false
    g_stash                = stash_make_empty()
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

    if cw.world_is_valid(w, w.player_id) &&
       cw.world_has_component(w, w.player_id, .Transform) {
        set_audio_listener(cw.world_get_transform(w, w.player_id).position)
    }

    if input_pressed(.F1) && g_is_host && !g_console_open &&
       (g_playing_state == .Editor || g_playing_state == .Gameplay || g_playing_state == .Hub) {
        editor_toggle()
    }
    update_lighting_widget()

    if !g_console_open {
        // ── World-state specific update ─────────────────────────────────────
        switch g_playing_state {

        case .Editor:
            update_editor(dt)

        case .Hub:
            // input_is_gameplay() is true when no panel is open (mode == .Gameplay)
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
                // Cycle loot filter: Normal → Rare → Epic → Legendary → Normal
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
            // All interaction is handled inside the draw procs.

        }

        // ── Panel-specific update (active when mode == .UI) ─────────────────
        // ESC to close the topmost panel is handled universally in the main
        // loop AFTER this block, so individual cases only do what is unique
        // to that panel (button logic, sub-state updates, quit detection).
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
                case .Settings, .LevelSelect, .Inventory, .Stats:
                    // No panel-specific update needed; universal ESC and
                    // mouse clicks inside the draw proc handle interaction.
                }
            }
        }
    }

    if g_playing_state != .DeathScreen && g_playing_state != .ExtractScreen {
        local_frame := collect_local_input() if playing_collects_input() else p2p.InputFrame{}
        g_accumulator += f64(dt)
        for g_accumulator >= f64(TICK_DT) {
            do_sim_tick(&g_sim, local_frame, TICK_DT)
            g_accumulator -= f64(TICK_DT)
            local_frame.actions = {}
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
    draw_tilemap()
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
    draw_mutation_workbench_world(w)
    draw_stash_world(w)
    draw_enemy_mutation_auras(w)
    draw_water_puddles()
    draw_fire_patches()
    draw_barrels()
    draw_status_effects(w)
    draw_ground_item_labels(w)
    draw_explosions()
    update_draw_dmg_numbers(rl.GetFrameTime())
    rl.EndMode2D()

    draw_editor_hud()
    if !g_editor_mode {
        update_entity_hover(w)
        draw_boss_warning()
        draw_entity_inspect_hud(w)
        draw_raid_timer()
        draw_hud(w)

        // Hub HUD persists while LevelSelect panel is open (world stays .Hub).
        if g_playing_state == .Hub {
            draw_hub_hud(w)
        }

        // World-state overlays that are not managed by UIManager.
        switch g_playing_state {
        case .ExtractScreen:
            draw_extract_screen(w)
        case .DeathScreen:
            draw_death_screen(w)
        case .Gameplay, .Hub, .Editor:
            // no extra overlay
        }

        draw_levelup_flash()
        draw_loot_filter_hud()
    }
    // NOTE: ui_draw() is called from the main loop (not here) so it runs
    // in all app states and fades work across main-menu and playing alike.
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

    ai_paths_init()
    defer ai_paths_destroy()

    level_data_init()
    defer level_data_destroy()

    if !loot_table_load("data/loot_table.csv") { return }
    defer loot_table_destroy()

    {
        defs, ok := load_entity_defs("data/entities.json")
        if !ok { return }
        g_entity_defs = defs
    }
    defer destroy_entity_defs(g_entity_defs)

    chars_load_all()
    _mm_init()

    for !rl.WindowShouldClose() && !g_should_exit {
        dt := rl.GetFrameTime()
        defer free_all(context.temp_allocator)

        update_clay_input()
        input_begin_frame()   // resets consumption, derives mode from ui_any()
        update_audio()
        update_fade(dt)
        update_console(dt)

        switch g_app_state {
        case .MainMenu:
            update_main_menu(dt)
        case .Connecting:
            update_connecting(dt)
        case .Playing:
            update_playing(dt)
        }

        // Universal ESC: close topmost UI layer in any app state.
        // Per-panel updates above run first so they can consume the key
        // (e.g. cancelling a rebind-listen) before this handler sees it.
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

        // UI panels are rendered last (on top of everything) across all
        // app states so Settings/Keybinds work from the main menu too.
        {
            ui_w := (^cw.World)(nil)
            if g_app_state == .Playing && g_sim_alive {
                ui_w = &g_sim.world
            }
            ui_draw(ui_w)
        }

        draw_fade()
        draw_console()
        rl.EndDrawing()
    }

    if g_sim_alive { shutdown_game() }
}
