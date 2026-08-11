package main

import rl   "vendor:raylib"
import      "core:os"
import      "core:strings"
import json "core:encoding/json"
import      "core:fmt"

// ---------------------------------------------------------------------------
// Prerendered level modules
//
// Levels are composed from hand-placed prerendered iso images — rooms, connectors,
// landmarks — while collision/gameplay lives in the tile grid (painted invisibly in
// the editor, same model as the hub's Town.png). A module is purely visual + a tile
// footprint used for grid-snapped placement; collision is authored separately.
//
// Manifest: data/sprites/modules/modules.json
//   { "modules": { "<id>": { "file": "<png stem>", "w": <tiles>, "h": <tiles>,
//                            "off_x": <px>, "off_y": <px> }, ... } }
// Images: data/sprites/modules/<file>.png
// ---------------------------------------------------------------------------

MODULE_DIR :: "data/sprites/modules/"

ModuleDef :: struct {
    id:    string,
    tex:   rl.Texture2D,
    w, h:  int,   // footprint in tiles (grid snapping / editor preview)
    off_x: f32,   // iso-space draw offset for fine art alignment
    off_y: f32,
}

// A placed module instance within a level.
LevelModule :: struct {
    def_idx: int,   // index into g_modules (-1 if the id wasn't found in the manifest)
    tx, ty:  i16,   // tile position of the module's origin
}

g_modules:      [dynamic]ModuleDef
g_module_index: map[string]int

module_registry_init :: proc() {
    g_modules      = make([dynamic]ModuleDef)
    g_module_index = make(map[string]int)

    data, ok := os.read_entire_file(MODULE_DIR + "modules.json")
    if !ok { return }   // no manifest yet — module system stays dormant
    defer delete(data)

    root, err := json.parse(data)
    if err != .None {
        fmt.eprintfln("[modules] failed to parse modules.json: %v", err)
        return
    }
    defer json.destroy_value(root)

    obj, obj_ok := root.(json.Object)
    if !obj_ok { return }
    mods, m_ok := obj["modules"].(json.Object)
    if !m_ok { return }

    for name, val in mods {
        o, ook := val.(json.Object)
        if !ook { continue }

        def := ModuleDef{
            id    = strings.clone(name),
            w     = max(_mj_int(o, "w", 1), 1),
            h     = max(_mj_int(o, "h", 1), 1),
            off_x = _mj_f32(o, "off_x", 0),
            off_y = _mj_f32(o, "off_y", 0),
        }
        file := _mj_str(o, "file", name)
        path := strings.concatenate({ MODULE_DIR, file, ".png" }, context.temp_allocator)
        pcs  := strings.clone_to_cstring(path, context.temp_allocator)
        if rl.FileExists(pcs) {
            def.tex = rl.LoadTexture(pcs)
            rl.SetTextureFilter(def.tex, .BILINEAR)
        } else {
            fmt.eprintfln("[modules] missing image: %s", path)
        }

        g_module_index[def.id] = len(g_modules)
        append(&g_modules, def)
    }
}

module_registry_destroy :: proc() {
    for m in g_modules { if m.tex.id != 0 { rl.UnloadTexture(m.tex) } }
    delete(g_modules)
    delete(g_module_index)
}

module_index_by_name :: proc(name: string) -> int {
    if idx, ok := g_module_index[name]; ok { return idx }
    return -1
}

module_count :: proc() -> int { return len(g_modules) }

module_name :: proc(idx: int) -> string {
    if idx >= 0 && idx < len(g_modules) { return g_modules[idx].id }
    return ""
}

// Place a module at a tile origin, replacing any module already anchored there.
module_place_at :: proc(def_idx, tx, ty: int) {
    if def_idx < 0 || def_idx >= len(g_modules) { return }
    for i := len(g_level_data.modules) - 1; i >= 0; i -= 1 {
        m := g_level_data.modules[i]
        if int(m.tx) == tx && int(m.ty) == ty { ordered_remove(&g_level_data.modules, i) }
    }
    append(&g_level_data.modules, LevelModule{ def_idx = def_idx, tx = i16(tx), ty = i16(ty) })
}

// Remove the topmost module whose footprint covers the tile.
module_erase_at :: proc(tx, ty: int) {
    for i := len(g_level_data.modules) - 1; i >= 0; i -= 1 {
        m := g_level_data.modules[i]
        if m.def_idx < 0 || m.def_idx >= len(g_modules) { continue }
        def := g_modules[m.def_idx]
        if tx >= int(m.tx) && tx < int(m.tx) + def.w && ty >= int(m.ty) && ty < int(m.ty) + def.h {
            ordered_remove(&g_level_data.modules, i)
            return
        }
    }
}

// Draw a translucent ghost of a module at a tile origin (editor placement preview).
module_draw_ghost :: proc(def_idx, tx, ty: int) {
    if def_idx < 0 || def_idx >= len(g_modules) { return }
    def := g_modules[def_idx]
    if def.tex.id == 0 { return }
    iso := world_to_iso_xy(f32(tx * TILE_SIZE), f32(ty * TILE_SIZE))
    rl.DrawTextureEx(def.tex, { iso.x + def.off_x, iso.y + def.off_y }, 0, 1.0, rl.Color{ 255, 255, 255, 130 })
}

// Draw the current level's placed modules — flat, behind entities, painter-sorted
// back-to-front in iso (by tx+ty). Called in the raid world pass in place of the tilemap.
draw_level_modules :: proc() {
    n := len(g_level_data.modules)
    if n == 0 { return }

    order := make([]int, n, context.temp_allocator)
    for i in 0..<n { order[i] = i }
    for i in 1..<n {
        j := i
        for j > 0 {
            a := g_level_data.modules[order[j-1]]
            b := g_level_data.modules[order[j]]
            if int(a.tx) + int(a.ty) <= int(b.tx) + int(b.ty) { break }
            order[j-1], order[j] = order[j], order[j-1]
            j -= 1
        }
    }

    for oi in order {
        m := g_level_data.modules[oi]
        if m.def_idx < 0 || m.def_idx >= len(g_modules) { continue }
        def := g_modules[m.def_idx]
        if def.tex.id == 0 { continue }
        iso := world_to_iso_xy(f32(int(m.tx) * TILE_SIZE), f32(int(m.ty) * TILE_SIZE))
        rl.DrawTextureEx(def.tex, { iso.x + def.off_x, iso.y + def.off_y }, 0, 1.0, rl.WHITE)
    }
}


@(private = "file")
_mj_int :: proc(o: json.Object, k: string, d: int) -> int {
    if v, ok := o[k]; ok {
        #partial switch n in v { case json.Integer: return int(n); case json.Float: return int(n) }
    }
    return d
}
@(private = "file")
_mj_f32 :: proc(o: json.Object, k: string, d: f32) -> f32 {
    if v, ok := o[k]; ok {
        #partial switch n in v { case json.Float: return f32(n); case json.Integer: return f32(n) }
    }
    return d
}
@(private = "file")
_mj_str :: proc(o: json.Object, k: string, d: string) -> string {
    if v, ok := o[k]; ok {
        #partial switch s in v { case string: return s }
    }
    return d
}
