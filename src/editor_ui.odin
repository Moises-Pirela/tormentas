package main

import      "core:fmt"
import      "core:strings"
import ecs  "cw:clockwork"
import im   "../deps/imgui/imgui"
import p2p  "p2p"

EditorMode :: enum u8 {
    Edit,
    Live,
}

g_ed_mode: EditorMode = .Edit

ed_set_mode :: proc(m: EditorMode) {
    if m == g_ed_mode { return }
    g_ed_mode = m

    if !g_sim_alive { return }
    w := &g_sim.world

    switch m {
    case .Live:
        g_sim.state = .Running

    case .Edit:
        fire_system_reset()
        level_clear(w)
        director_init()
        level_apply(w)
        door_init_blockers(w)
        if g_hub_active { hub_apply(w) }
        spawn_players(w)
        g_sim.state = .Paused
    }
}

ed_mode_enter_editor :: proc() {
    g_ed_mode = .Live
    ed_set_mode(.Edit)
}

ed_mode_exit_editor :: proc() {
    g_ed_mode = .Live
    if g_sim_alive { g_sim.state = .Running }
}

DevPanel :: enum u8 {
    Tools, Paint, Grid, Levels, Inspector,
}

DEV_PANEL_TITLES := [DevPanel]cstring{
    .Tools     = "Tools",
    .Paint     = "Paint",
    .Grid      = "Grid & Camera",
    .Levels    = "Levels",
    .Inspector = "Inspector",
}

g_ed_panel_open: [DevPanel]bool = { .Tools = true, .Paint = true, .Grid = true, .Levels = true, .Inspector = true }

@(private = "file") g_ed_layout_reset:  bool
@(private = "file") g_ed_live_insp:     DevInspectorState
@(private = "file") g_ed_def_filter:    [48]u8
@(private = "file") g_ed_def_filter_n:  int
@(private = "file") g_ed_name_buf:      [ED_NAME_LEN]u8
@(private = "file") g_ed_name_n:        int
@(private = "file") g_ed_name_for:      int = -1
@(private = "file") g_ed_confirm_clear: bool

ED_BRUSHES := [?]EditorBrush{ .HubCollision, .HubWalkable, .Oil, .Fire, .Module, .Erase }

DOCK_FLAG_DOCKSPACE :: i32(1 << 10)

ed_brush_label :: proc(b: EditorBrush) -> string {
    #partial switch b {
    case .HubCollision: return "Collision"
    case .HubWalkable:  return "Walkable"
    case .Oil:          return "Oil"
    case .Fire:         return "Fire"
    case .Module:       return "Module"
    case .Erase:        return "Erase"
    }
    return "?"
}

devui_request_layout_reset :: proc() { g_ed_layout_reset = true }

devui_tools_frame :: proc() {
    show_menu := g_editor_mode || g_anim_ed.open
    if show_menu { _devui_main_menu() }

    if g_editor_mode {
        _devui_dockspace()
        if g_ed_panel_open[.Tools]     { _ed_tools_window() }
        if g_ed_panel_open[.Paint]     { _ed_paint_window() }
        if g_ed_panel_open[.Grid]      { _ed_grid_window() }
        if g_ed_panel_open[.Levels]    { _ed_levels_window() }
        if g_ed_panel_open[.Inspector] { _ed_inspector_window() }
        _ed_save_toast()
        _ed_confirm_clear_modal()
    }

    anim_editor_ui()
    console_ui()
    lighting_ui()
    dbg_inspector_ui()
    if g_devui_demo { im.ShowDemoWindow(&g_devui_demo) }
}

@(private = "file")
_devui_main_menu :: proc() {
    if !im.BeginMainMenuBar() { return }
    defer im.EndMainMenuBar()

    if g_editor_mode && im.BeginMenu("File") {
        if im.MenuItem("Save level", "Ctrl+S") { _ed_save_level() }
        if im.MenuItem("Reload level", "Ctrl+L") { _ed_reload_level() }
        im.Separator()
        if im.MenuItem("New level") { _ed_new_level() }
        if im.MenuItem("Clear level...") { g_ed_confirm_clear = true }
        im.Separator()
        if im.MenuItem("Exit editor", "F1") { editor_toggle() }
        im.EndMenu()
    }
    if g_editor_mode && im.BeginMenu("Mode") {
        if im.MenuItem("Edit (simulation paused)", "F5", g_ed_mode == .Edit) { ed_set_mode(.Edit) }
        if im.MenuItem("Live (playtest)", "F5", g_ed_mode == .Live) { ed_set_mode(.Live) }
        im.EndMenu()
    }
    if im.BeginMenu("Tools") {
        if im.MenuItem("Level editor", "F1", g_editor_mode, g_is_host && g_app_state == .Playing) { editor_toggle() }
        if im.MenuItem("Animation editor", "F3", g_anim_ed.open, g_is_host) {
            if g_anim_ed.open { anim_editor_close() } else { anim_editor_open() }
        }
        if im.MenuItem("Lighting", "F2", g_light_widget_open) { g_light_widget_open = !g_light_widget_open }
        if im.MenuItem("ECS inspector", "F6", g_dbg_insp_open, g_sim_alive) { dbg_inspector_toggle() }
        if im.MenuItem("Console", "`", g_console_open) { console_set_open(!g_console_open) }
        im.EndMenu()
    }
    if g_editor_mode && im.BeginMenu("View") {
        for p in DevPanel {
            if im.MenuItem(DEV_PANEL_TITLES[p], nil, g_ed_panel_open[p]) { g_ed_panel_open[p] = !g_ed_panel_open[p] }
        }
        im.Separator()
        if im.MenuItem("Show grid", "G", g_ed_grid_visible) { g_ed_grid_visible = !g_ed_grid_visible }
        if im.MenuItem("Snap to tile grid", nil, g_ed_snap) { g_ed_snap = !g_ed_snap }
        im.Separator()
        if im.MenuItem("Reset layout") {
            for p in DevPanel { g_ed_panel_open[p] = true }
            g_ed_layout_reset = true
        }
        if im.MenuItem("Dear ImGui demo", nil, g_devui_demo) { g_devui_demo = !g_devui_demo }
        im.EndMenu()
    }

    if g_editor_mode {
        mode_col := DEVUI_GOLD if g_ed_mode == .Edit else DEVUI_GREEN
        mode_txt := "EDIT" if g_ed_mode == .Edit else "LIVE"
        im.Separator()
        ui_text_col(mode_col, "%s", mode_txt)
        ents := world_entity_count(&g_sim.world) if g_sim_alive else 0
        ui_hint("level %d  %s   entities %d   zoom %.2fx", g_ed_level, _ed_level_name(g_ed_level), ents, g_ed_zoom)
    } else if g_anim_ed.open {
        im.Separator()
        ui_text_col(DEVUI_GOLD, "ANIMATION EDITOR")
    }
}

@(private = "file")
_devui_dockspace :: proc() {
    vp := im.GetMainViewport()
    id := im.GetID("TormentasDock")
    if g_ed_layout_reset || im.DockBuilderGetNode(id) == nil {
        g_ed_layout_reset = false
        im.DockBuilderRemoveNode(id)
        flags := transmute(im.DockNodeFlags)DOCK_FLAG_DOCKSPACE
        flags += { .PassthruCentralNode }
        im.DockBuilderAddNode(id, flags)
        im.DockBuilderSetNodeSize(id, vp.WorkSize)
        rest:   im.ID
        left := im.DockBuilderSplitNode(id, .Left, 0.19, nil, &rest)
        right := im.DockBuilderSplitNode(rest, .Right, 0.25, nil, &rest)
        bottom := im.DockBuilderSplitNode(rest, .Down, 0.24, nil, &rest)
        left_lo: im.ID
        left_hi := im.DockBuilderSplitNode(left, .Up, 0.55, nil, &left_lo)
        im.DockBuilderDockWindow("Tools", left_hi)
        im.DockBuilderDockWindow("Paint", left_hi)
        im.DockBuilderDockWindow("Levels", left_lo)
        im.DockBuilderDockWindow("Grid & Camera", left_lo)
        im.DockBuilderDockWindow("Inspector", right)
        im.DockBuilderDockWindow("Lighting", right)
        im.DockBuilderDockWindow("ECS Inspector", right)
        im.DockBuilderDockWindow("Console", bottom)
        im.DockBuilderFinish(id)
    }
    im.DockSpaceOverViewport(id, vp, { .PassthruCentralNode })
}

@(private = "file")
_ed_save_level :: proc() {
    level_save(g_ed_level)
    ed_refresh_exists()
    g_ed_save_msg = 2.0
}

@(private = "file")
_ed_reload_level :: proc() {
    fire_system_reset()
    level_clear(&g_sim.world)
    director_init()
    level_load(g_ed_level)
    level_apply(&g_sim.world)
    door_init_blockers(&g_sim.world)
    if g_hub_active { hub_apply(&g_sim.world) }
    spawn_players(&g_sim.world)
    p2p.session_send_level_load(&g_session, g_ed_level)
}

@(private = "file")
_ed_new_level :: proc() {
    for i in 1..=ED_MAX_LEVELS {
        if g_ed_level_exists[i] { continue }
        g_ed_level = i
        ed_clear_all()
        level_save(g_ed_level)
        ed_refresh_exists()
        ed_rebuild_filtered()
        g_ed_save_msg = 2.0
        break
    }
}

@(private = "file")
_ed_level_name :: proc(idx: int) -> string {
    if idx < 0 || idx > ED_MAX_LEVELS { return "" }
    nm := &g_ed_level_names[idx]
    n  := 0
    for n < ED_NAME_LEN && nm[n] != 0 { n += 1 }
    return n == 0 ? "(unnamed)" : string(nm[:n])
}

@(private = "file")
_ed_tools_window :: proc() {
    defer im.End()
    if !im.Begin("Tools", &g_ed_panel_open[.Tools]) { return }

    im.SeparatorText("Tool")
    for t, i in EditorTool {
        if i > 0 { im.SameLine() }
        if im.RadioButton(fmt.ctprintf("%v", t), g_ed_tool == t) { g_ed_tool = t }
    }
    im.Checkbox("Snap to tile grid", &g_ed_snap)
    ui_hint("Hold %s while dragging the gizmo to toggle snap.", "Cmd" when ODIN_OS == .Darwin else "Ctrl")

    im.SeparatorText("Place entity")
    im.SetNextItemWidth(-1)
    ui_input_buf("##deffilter", g_ed_def_filter[:], &g_ed_def_filter_n, {}, "filter definitions")
    filter := strings.to_lower(string(g_ed_def_filter[:g_ed_def_filter_n]), context.temp_allocator)

    if im.BeginChild("##defs", { 0, 0 }, { .Borders }) {
        for def, i in g_entity_defs {
            if filter != "" && !strings.contains(strings.to_lower(def.name, context.temp_allocator), filter) { continue }
            if im.Selectable(fmt.ctprintf("%s##def%d", def.name, i), i == g_ed_def_idx && g_ed_tool == .Place) {
                g_ed_def_idx = i
                g_ed_tool    = .Place
            }
        }
    }
    im.EndChild()
}

@(private = "file")
_ed_paint_window :: proc() {
    defer im.End()
    if !im.Begin("Paint", &g_ed_panel_open[.Paint]) { return }

    im.SeparatorText("Brush")
    for b, i in ED_BRUSHES {
        _, raw := ed_brush_colors(b)
        sw := ed_brush_display_color(raw)
        if b == .Erase { sw = { 235, 85, 75, 255 } }
        im.ColorButton(fmt.ctprintf("##sw%d", i), { f32(sw.r) / 255, f32(sw.g) / 255, f32(sw.b) / 255, 1 },
            { .NoTooltip, .NoPicker, .NoDragDrop }, { im.GetFrameHeight() * 0.7, im.GetFrameHeight() * 0.7 })
        im.SameLine()
        if im.Selectable(fmt.ctprintf("%s##brush", ed_brush_label(b)), g_ed_brush == b && g_ed_tool == .Paint) {
            g_ed_brush = b
            g_ed_tool  = .Paint
        }
        im.SameLine(im.GetContentRegionAvail().x - 10)
        ui_hint("%d", i + 1)
    }

    if g_ed_brush == .Module {
        im.SeparatorText("Module")
        ui_text("%s", module_count() > 0 ? module_name(g_ed_module_idx) : "(no modules loaded)")
        if im.Button("< Prev") { ed_cycle_module(-1) }
        ui_tooltip("Comma")
        im.SameLine()
        if im.Button("Next >") { ed_cycle_module(+1) }
        ui_tooltip("Period")
    }

    im.SeparatorText("Size")
    step := g_hub_active ? g_ed_cell_size : TILE_SIZE
    size := g_ed_brush_size / max(step, 1)
    im.SetNextItemWidth(-1)
    if ui_input_i32("##brushsize", &size, 1, max(512 / max(step, 1), 1)) {
        g_ed_brush_size = size * step
    }
    ui_hint("%d px  (Shift+[ / Shift+])", g_ed_brush_size)

    im.Spacing()
    if g_ed_tool == .Paint || g_ed_tool == .Erase {
        ui_hint("LMB paints, RMB selects an object or erases.")
    } else {
        ui_hint("Painting is off: pick a brush or the Paint tool.")
    }
}

@(private = "file")
_ed_grid_window :: proc() {
    defer im.End()
    if !im.Begin("Grid & Camera", &g_ed_panel_open[.Grid]) { return }

    im.Checkbox("Show grid  (G)", &g_ed_grid_visible)
    cell := g_ed_cell_size
    if ui_input_i32("Cell size (px)", &cell, 16, 1024, 16) { ed_set_cell_size(cell) }

    cols, rows := i32(g_ed_grid_cols), i32(g_ed_grid_rows)
    if im.SliderInt("Grid X", &cols, 1, 200) { g_ed_grid_cols = int(cols) }
    if im.SliderInt("Grid Y", &rows, 1, 200) { g_ed_grid_rows = int(rows) }
    if im.Button("Reset grid (all walkable)") { ed_reset_grid_walkable() }
    ui_hint("Hold Shift while painting to snap the brush to the grid.")

    if im.CollapsingHeader("Camera bounds", { .DefaultOpen }) {
        CAM_RANGE :: f32(8192)
        im.DragFloat("Left",  &g_level_data.cam_lims[0], 4, -CAM_RANGE, CAM_RANGE, "%.0f")
        im.DragFloat("Right", &g_level_data.cam_lims[1], 4, -CAM_RANGE, CAM_RANGE, "%.0f")
        im.DragFloat("Top",   &g_level_data.cam_lims[2], 4, -CAM_RANGE, CAM_RANGE, "%.0f")
        im.DragFloat("Lower", &g_level_data.cam_lims[3], 4, -CAM_RANGE, CAM_RANGE, "%.0f")
        if im.Button("Reset to level defaults") { g_level_data.cam_lims = {} }
    }
    im.Separator()
    ui_hint("zoom %.2fx   tiles %d", g_ed_zoom, len(g_tilemap))
}

@(private = "file")
_ed_levels_window :: proc() {
    defer im.End()
    if !im.Begin("Levels", &g_ed_panel_open[.Levels]) { return }

    if g_ed_name_for != g_ed_level {
        g_ed_name_for = g_ed_level
        g_ed_name_n   = 0
        nm := &g_ed_level_names[g_ed_level]
        for g_ed_name_n < ED_NAME_LEN - 1 && nm[g_ed_name_n] != 0 {
            g_ed_name_buf[g_ed_name_n] = nm[g_ed_name_n]
            g_ed_name_n += 1
        }
    }
    im.SetNextItemWidth(-1)
    if ui_input_buf("##lvlname", g_ed_name_buf[:], &g_ed_name_n, {}, "level name") {
        nm := &g_ed_level_names[g_ed_level]
        nm^ = {}
        copy(nm[:ED_NAME_LEN - 1], g_ed_name_buf[:g_ed_name_n])
        ed_meta_save()
    }

    w := (im.GetContentRegionAvail().x - im.GetStyle().ItemSpacing.x) * 0.5
    if im.Button("Save", { w, 0 }) { _ed_save_level() }
    im.SameLine()
    if im.Button("Load", { w, 0 }) {
        level_load(g_ed_level)
        p2p.session_send_level_load(&g_session, g_ed_level)
    }
    if im.Button("New level", { w, 0 }) { _ed_new_level() }
    im.SameLine()
    if im.Button("Clear...", { w, 0 }) { g_ed_confirm_clear = true }

    im.SeparatorText(fmt.ctprintf("Levels (%d)", g_ed_filtered_count))
    if im.BeginChild("##levels", { 0, 0 }, { .Borders }) {
        for fi in 0..<g_ed_filtered_count {
            idx := g_ed_filtered[fi]
            if im.Selectable(fmt.ctprintf("%02d  %s##lvl", idx, _ed_level_name(idx)), idx == g_ed_level) && idx != g_ed_level {
                g_ed_level = idx
                ed_rebuild_filtered()
                level_load(g_ed_level)
                p2p.session_send_level_load(&g_session, g_ed_level)
            }
        }
    }
    im.EndChild()
}

@(private = "file")
_ed_inspector_window :: proc() {
    defer im.End()
    if !im.Begin("Inspector", &g_ed_panel_open[.Inspector]) { return }

    ed_entity_validate()
    sel := ed_entity_selected()
    if sel != nil {
        _ed_level_entity_ui(sel)
        return
    }
    if ed_insp_has_selection() {
        ed_insp_object_ui()
        return
    }
    ui_hint("Nothing selected.")
    im.Spacing()
    im.TextWrapped("Select tool + LMB picks a placed entity. In Paint mode, RMB on a lever, chest, NPC or other tile object selects it.")
}

@(private = "file")
_ed_level_entity_ui :: proc(sel: ^LevelEntity) {
    ui_text_col(DEVUI_GOLD, "%s", sel.def)
    ui_hint("level entity #%d", g_ed_sel_entity)

    pos := [2]f32{ sel.position[0], sel.position[1] }
    if im.DragFloat2("Position", &pos, 1, 0, 0, "%.0f") {
        sel.position[0] = pos[0]
        sel.position[1] = pos[1]
        if g_sim_alive && world_is_valid(&g_sim.world, sel.live_id) &&
           world_has_component(&g_sim.world, sel.live_id, .Transform) {
            comp_get(&g_sim.world, sel.live_id, .Transform, TransformComp).position = sel.position
        }
    }
    if im.IsItemDeactivatedAfterEdit() { ed_entity_respawn_world() }

    half := (im.GetContentRegionAvail().x - im.GetStyle().ItemSpacing.x) * 0.5
    if im.Button("Capture overrides", { half, 0 }) { ed_entity_capture() }
    ui_tooltip("Store live component edits on this level entity")
    im.SameLine()
    if im.Button("Reset overrides", { half, 0 }) {
        level_entity_clear_overrides(g_ed_sel_entity)
        ed_entity_respawn_world()
    }
    im.PushStyleColorImVec4(.Button, { 0.45, 0.14, 0.12, 1 })
    if im.Button("Delete entity", { -1, 0 }) {
        im.PopStyleColor()
        ed_entity_delete_selected()
        return
    }
    im.PopStyleColor()
    ui_tooltip("Delete key")

    if len(sel.overrides) > 0 && im.CollapsingHeader(fmt.ctprintf("Authored overrides (%d)###ovr", len(sel.overrides)), { .DefaultOpen }) {
        if im.BeginTable("##ovr", 2, im.TableFlags_RowBg | im.TableFlags_BordersInnerV) {
            for o in sel.overrides {
                im.TableNextRow()
                im.TableNextColumn(); ui_text("%v.%s", o.component, o.path)
                im.TableNextColumn(); ui_text("%s", o.value)
            }
            im.EndTable()
        }
    }

    if g_sim_alive && world_is_valid(&g_sim.world, sel.live_id) {
        if im.CollapsingHeader("Live components", { .DefaultOpen }) {
            devui_inspector_init(&g_ed_live_insp)
            g_ed_live_insp.authority.role = .Host
            if g_ed_live_insp.insp.selected != sel.live_id {
                ecs.inspector_select(&g_ed_live_insp.insp, &g_sim.world.base, sel.live_id)
            }
            devui_entity_fields(&g_ed_live_insp, &g_sim.world.base, &g_ed_live_insp.authority)
        }
    }
}

@(private = "file")
_ed_save_toast :: proc() {
    if g_ed_save_msg <= 0 { return }
    vp := im.GetMainViewport()
    im.SetNextWindowPos({ vp.WorkPos.x + vp.WorkSize.x * 0.5, vp.WorkPos.y + 40 }, .Always, { 0.5, 0 })
    im.SetNextWindowBgAlpha(clamp(g_ed_save_msg, 0, 1) * 0.9)
    if im.Begin("##savetoast", nil, im.WindowFlags_NoDecoration + im.WindowFlags_NoInputs + im.WindowFlags_NoNav + { .NoSavedSettings, .NoFocusOnAppearing, .NoDocking, .AlwaysAutoResize }) {
        ui_text_col(DEVUI_GREEN, "Level %d saved", g_ed_level)
    }
    im.End()
}

@(private = "file")
_ed_confirm_clear_modal :: proc() {
    if g_ed_confirm_clear {
        im.OpenPopup("Clear level?")
        g_ed_confirm_clear = false
    }
    if im.BeginPopupModal("Clear level?", nil, { .AlwaysAutoResize }) {
        ui_text("Remove every tile, object and entity from level %d?", g_ed_level)
        ui_hint("Nothing is written to disk until you save.")
        im.Spacing()
        if im.Button("Clear", { 120, 0 }) {
            ed_clear_all()
            im.CloseCurrentPopup()
        }
        im.SameLine()
        if im.Button("Cancel", { 120, 0 }) { im.CloseCurrentPopup() }
        im.EndPopup()
    }
}
