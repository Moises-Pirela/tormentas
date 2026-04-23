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
    cw.sim_register_system(&g_sim, { .LateUpdate  }, damage_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, camera_follow_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, wall_collision_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, projectile_wall_system)
    cw.sim_register_system(&g_sim, { .LateUpdate  }, level_exit_system)

    w := &g_sim.world

    g_sim.state = .Running

    w.local_player_slot = g_session.local_slot

    level_load(0)
    level_apply(w)
    hub_apply(w)
    spawn_players(w)
    load_player(w, w.player_id)

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
        cw.destroy_simulation(&g_sim)
        g_sim_alive = false
    }

    p2p.session_shutdown(&g_session)
    g_local_hist = {}
    g_stall_acc  = 0
    g_accumulator = 0

    set_playing_state(.Gameplay)
    g_pending_level_switch = 0
    g_raid_timer           = 0
    g_is_host            = false
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
        inv_open := g_playing_state == .Inventory || g_playing_state == .Shop
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

    if rl.IsKeyPressed(.F1) && g_is_host && !g_console_open {
        if g_playing_state == .Editor {
            set_playing_state(.Hub if g_hub_active else .Gameplay)
        } else if g_playing_state == .Gameplay || g_playing_state == .Hub {
            set_playing_state(.Editor)
        }
    }
    update_lighting_widget()

    if !g_console_open {
    switch g_playing_state {

    case .Hub:
        if rl.IsKeyPressed(rl.KeyboardKey(g_binds.pause)) {
            set_playing_state(.PauseMenu)
        }
        if rl.IsKeyPressed(rl.KeyboardKey(g_binds.open_inventory)) {
            set_playing_state(.Inventory)
        }
        if rl.IsKeyPressed(rl.KeyboardKey(g_binds.open_stats)) {
            set_playing_state(.Stats)
        }
        update_mutation_workbench(w)
        update_shop(w)
        update_hub_portal(w)

    case .LevelSelect:
        if rl.IsKeyPressed(.ESCAPE) {
            set_playing_state(.Hub)
        }

    case .Editor:
        update_editor(dt)

    case .PauseMenu:
        update_keybinds_screen()
        if update_pause_menu() {
            fade_to_black(_on_black_to_menu)
            return
        }
        if !g_paused {
            set_playing_state(.Hub if g_hub_active else .Gameplay)
        }

    case .ExtractScreen:

    case .DeathScreen:

    case .Gameplay, .Inventory, .Stats, .MutationTree, .Shop:
        if rl.IsKeyPressed(rl.KeyboardKey(g_binds.pause)) {
            if g_playing_state != .Gameplay {
                set_playing_state(.Hub if g_hub_active else .Gameplay)
            } else {
                set_playing_state(.PauseMenu)
            }
        }
        if g_playing_state == .Gameplay {
            if rl.IsKeyPressed(rl.KeyboardKey(g_binds.open_inventory)) {
                set_playing_state(.Inventory)
            }
            if rl.IsKeyPressed(rl.KeyboardKey(g_binds.open_stats)) {
                set_playing_state(.Stats)
            }
        }
        #partial switch g_playing_state {
        case .Inventory:    update_inventory(w)
        case .Stats:        update_stats_screen(w)
        case .MutationTree: update_mutation_tree(w)
        case .Shop:
            update_inventory(w)
            update_shop(w)
        case .Gameplay:
            update_mutation_workbench(w)
            update_shop(w)
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
    if g_playing_state == .Hub || g_playing_state == .LevelSelect {
        draw_hub_world(w)
    }
    draw_editor_world()
    draw_ground_items(w)
    draw_melee_arcs(w)
    draw_projectiles(w)
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
    draw_world_npcs(w)
    draw_enemies(w)
    draw_player(w)
    rl.EndMode2D()
    rl.EndTextureMode()

    draw_directional_sprite_composite(w)

    draw_cloud_shadow_field()
    draw_world_god_rays()
    if !g_editor_mode { draw_fog_and_lights(w) }

    rl.BeginMode2D(g_camera^)
    draw_mutation_workbench_world(w)
    update_draw_dmg_numbers(rl.GetFrameTime())
    rl.EndMode2D()

    draw_editor_hud()
    if !g_editor_mode {
        draw_boss_warning()
        draw_boss_hud(w)
        draw_raid_timer()
        draw_hud_clay(w)
        draw_ammo_ring(w)
        draw_ability_hud(w)

        switch g_playing_state {
        case .Hub:
            draw_hub_hud(w)
        case .LevelSelect:
            draw_hub_hud(w)
            draw_level_select(w)
        case .Gameplay:
            // no overlay
        case .Inventory:
            draw_inventory(w)
        case .Stats:
            draw_stats_screen(w)
        case .MutationTree:
            draw_mutation_tree(w)
        case .Shop:
            draw_inventory(w)
            draw_shop_hud(w)
        case .PauseMenu:
            draw_pause_menu()
            draw_keybinds_screen()
        case .ExtractScreen:
            draw_extract_screen(w)
        case .DeathScreen:
            draw_death_screen(w)
        case .Editor:
        }

        draw_levelup_flash()
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

    init_audio()
    defer shutdown_audio()

    init_clay()
    defer shutdown_clay()

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

    {
        defs, ok := load_entity_defs("data/entities.json")
        if !ok { return }
        g_entity_defs = defs
    }
    defer destroy_entity_defs(g_entity_defs)

    copy(g_player_name[:], "Wanderer")

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()
        defer free_all(context.temp_allocator)

        update_clay_input()
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

        draw_fade()
        draw_console()
        rl.EndDrawing()
    }

    if g_sim_alive { shutdown_game() }
}
