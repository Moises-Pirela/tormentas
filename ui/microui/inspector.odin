package tormentas_mu_inspector

import ecs "cw:clockwork"
import mu "vendor:microui"
import "core:fmt"

UiState :: struct {
    selected: ecs.EntityId,
    focused_id: mu.Id,
    text: [256]u8,
    text_len: int,
}

inspector_window :: proc(ctx: ^mu.Context, ui: ^UiState, inspector: ^ecs.Inspector, world: ^ecs.World, sim: ^ecs.Sim, rect: mu.Rect) {
    ecs.inspector_validate(inspector, world)
    if !mu.begin_window(ctx, "Entity Inspector", rect) { return }
    defer mu.end_window(ctx)
    mu.layout_row(ctx, []i32{-1}, 22)
    mu.label(ctx, ecs.inspector_authority_note(sim))
    for id in ecs.inspector_entities(world, inspector) {
        if .SUBMIT in mu.button(ctx, fmt.tprintf("Entity #%d", id)) { ecs.inspector_select(inspector, world, id) }
    }
    for row in ecs.inspector_rows(world, inspector) {
        if row.kind == .Component {
            mu.layout_row(ctx, []i32{-1}, 22)
            if .SUBMIT in mu.button(ctx, row.label) { ecs.inspector_toggle_collapsed(inspector, row.comp) }
        } else {
            mu.layout_row(ctx, []i32{140, -1}, 22)
            mu.label(ctx, row.label)
            value := ecs.field_text(row.field)
            if !row.field.editable || !ecs.inspector_editable(sim) || row.field.kind == .Group {
                mu.label(ctx, value)
            } else {
                id := mu.get_id(ctx, fmt.tprintf("%d:%d:%s", inspector.selected, row.comp, row.field.path))
                local_text: [256]u8
                local_len := min(len(value), len(local_text))
                copy(local_text[:], value[:local_len])
                buffer, count := local_text[:], &local_len
                if ui.selected == inspector.selected && ui.focused_id == id {
                    buffer, count = ui.text[:], &ui.text_len
                }
                result := mu.textbox_raw(ctx, buffer, count, id, mu.layout_next(ctx))
                if ctx.focus_id == id {
                    ui.selected, ui.focused_id = inspector.selected, id
                    ui.text_len = count^
                    copy(ui.text[:], buffer[:count^])
                }
                if .SUBMIT in result { ecs.field_set_text(row.field, string(buffer[:count^])) }
            }
        }
    }
}

stats_window :: proc(ctx: ^mu.Context, world: ^ecs.World, unused: rawptr, rect: mu.Rect) {
    if !mu.begin_window(ctx, "World Stats", rect) { return }
    defer mu.end_window(ctx)
    mu.layout_row(ctx, []i32{-1}, 22)
    mu.label(ctx, fmt.tprintf("Entities: %d", ecs.world_entity_count(world)))
    mu.label(ctx, fmt.tprintf("Tick: %d", world.tick))
}
