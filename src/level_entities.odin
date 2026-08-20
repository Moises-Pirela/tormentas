package main

import ecs "cw:clockwork"
import "core:strings"

FieldOverride :: struct {
    component: ComponentType,
    path:      string,
    value:     string,
}

LevelEntity :: struct {
    def:       string,
    position:  [3]f32,
    rotation:  f32,
    overrides: [dynamic]FieldOverride,

    live_id:   int,
}

level_entities_clear :: proc() {
    for &e in g_level_data.entities {
        delete(e.def)
        for o in e.overrides {
            delete(o.path)
            delete(o.value)
        }
        delete(e.overrides)
    }
    clear(&g_level_data.entities)
}

level_entity_add :: proc(def: string, pos: [3]f32, rotation: f32 = 0) -> int {
    append(&g_level_data.entities, LevelEntity{
        def      = strings.clone(def),
        position = pos,
        rotation = rotation,
        live_id  = INVALID_ENTITY,
    })
    return len(g_level_data.entities) - 1
}

level_entity_remove :: proc(idx: int) {
    if idx < 0 || idx >= len(g_level_data.entities) { return }
    e := &g_level_data.entities[idx]
    delete(e.def)
    for o in e.overrides {
        delete(o.path)
        delete(o.value)
    }
    delete(e.overrides)
    ordered_remove(&g_level_data.entities, idx)
}

level_entity_set_override :: proc(idx: int, ct: ComponentType, path, value: string) {
    if idx < 0 || idx >= len(g_level_data.entities) { return }
    e := &g_level_data.entities[idx]
    for &o in e.overrides {
        if o.component == ct && o.path == path {
            delete(o.value)
            o.value = strings.clone(value)
            return
        }
    }
    append(&e.overrides, FieldOverride{
        component = ct,
        path      = strings.clone(path),
        value     = strings.clone(value),
    })
}

level_entity_clear_overrides :: proc(idx: int) {
    if idx < 0 || idx >= len(g_level_data.entities) { return }
    e := &g_level_data.entities[idx]
    for o in e.overrides {
        delete(o.path)
        delete(o.value)
    }
    clear(&e.overrides)
}

level_entity_spawn :: proc(w: ^World, e: ^LevelEntity) -> int {
    def := find_entity_def(g_entity_defs, e.def)
    if def == nil { return INVALID_ENTITY }

    id := spawn_from_def(w, def)
    if id == INVALID_ENTITY { return id }

    if world_has_component(w, id, .Transform) {
        t := comp_get(w, id, .Transform, TransformComp)
        t.position = e.position
        t.rotation = e.rotation
    }

    for o in e.overrides {
        if !world_has_component(w, id, o.component) { continue }
        for f in ecs.comp_fields(&w.base, id, ecs.comp_id(o.component)) {
            if f.path != o.path { continue }
            ecs.field_set_text(f, o.value)
            break
        }
    }

    e.live_id = id
    return id
}

level_entities_apply :: proc(w: ^World) {
    for &e in g_level_data.entities {
        level_entity_spawn(w, &e)
    }
}

level_entity_snapshot :: proc(w: ^World, id: int, out: ^[dynamic]FieldOverride) {
    for o in out { delete(o.path); delete(o.value) }
    clear(out)
    if !world_is_valid(w, id) { return }

    for ct in ecs.inspector_components(&w.base, id) {
        if ComponentType(ct) == .Transform { continue }
        for f in ecs.comp_fields(&w.base, id, ct) {
            if !f.editable { continue }
            append(out, FieldOverride{
                component = ComponentType(ct),
                path      = strings.clone(f.path),
                value     = strings.clone(ecs.field_text(f)),
            })
        }
    }
}

level_entity_capture :: proc(w: ^World, idx: int, base: []FieldOverride) {
    if idx < 0 || idx >= len(g_level_data.entities) { return }
    e := &g_level_data.entities[idx]
    if !world_is_valid(w, e.live_id) { return }

    if world_has_component(w, e.live_id, .Transform) {
        t := comp_get(w, e.live_id, .Transform, TransformComp)
        e.position = t.position
        e.rotation = t.rotation
    }

    for b in base {
        if !world_has_component(w, e.live_id, b.component) { continue }
        for f in ecs.comp_fields(&w.base, e.live_id, ecs.comp_id(b.component)) {
            if f.path != b.path { continue }
            now := ecs.field_text(f)
            if now != b.value {
                level_entity_set_override(idx, b.component, b.path, now)
            }
            break
        }
    }
}
