package main


import rl   "vendor:raylib"
import clay "../clay"
import      "core:fmt"


COL_PARCH   :: rl.Color{ 222, 207, 162, 245 }
COL_CRIMSON :: rl.Color{ 178,  40,  36, 255 }
COL_BRASS   :: rl.Color{ 188, 150,  55, 235 }
COL_MUTED   :: rl.Color{ 128, 118,  88, 195 }
COL_PANEL   :: rl.Color{  10,   7,   5, 210 }
COL_RULE    :: rl.Color{ 130, 100,  38, 150 }
COL_SHIELD  :: rl.Color{  80, 180, 255, 220 }
COL_STAT    :: rl.Color{ 140, 195, 235, 230 }
COL_AFFIX   :: rl.Color{ 195, 168,  72, 235 }


UICustomKind :: enum u8 {
    None,
    Orb,
    AbilityChip,
    AmmoChip,
    InvSlot,
    WeaponSlot,
    InvAbility,
    GoldChip,
}


UICustomOrb :: struct {
    fill_ratio:   f32,
    shield_ratio: f32,
    fill_col:     rl.Color,
    bg_col:       rl.Color,
    value_text:   [8]u8,
    // portrait_idx: 0=none, 1=hp heart icon, 2-6=class portrait (g_selected_class_idx+2)
    portrait_idx: u8,
}

UICustomGold :: struct {
    gold_val: i32,
}


UICustomAbility :: struct {
    cd_ratio:    f32,
    charge_glow: bool,
    dance_glow:  bool,
    has_ability: bool,
    key_label:   [4]u8,
    name_label:  [24]u8,
}


UICustomAmmo :: struct {
    ammo_ratio:   f32,
    reload_ratio: f32,
    is_reloading: bool,
    is_melee:     bool,
    ammo_text:    [8]u8,
    wep_name:     [24]u8,
}


UICustomInvSlot :: struct {
    label:     [8]u8,
    item_name: [24]u8,
    has_item:  bool,
    is_target: bool,
}


UICustomWeaponSlot :: struct {
    type_label: [12]u8,
    item_name:  [24]u8,
    has_item:   bool,
    is_blocked: bool,
    is_target:  bool,
}


UICustomInvAbility :: struct {
    key_label:   [4]u8,
    name:        [24]u8,
    has_item:    bool,
    is_target:   bool,
    rarity_col:  rl.Color,
    trait_col:   rl.Color,
    level:       u8,
}

UICustomData :: struct {
    kind: UICustomKind,
    using _: struct #raw_union {
        orb:      UICustomOrb,
        ability:  UICustomAbility,
        ammo:     UICustomAmmo,
        inv_slot: UICustomInvSlot,
        wep_slot: UICustomWeaponSlot,
        inv_abil: UICustomInvAbility,
        gold:     UICustomGold,
    },
}


@(private = "file") _ui_arena:   [128]UICustomData
@(private = "file") _ui_arena_n: int

ui_frame_reset :: proc() {
    _ui_arena_n = 0
}


ui_push_custom :: proc(d: UICustomData) -> rawptr {
    assert(_ui_arena_n < len(_ui_arena), "UICustomData frame arena overflow")
    _ui_arena[_ui_arena_n] = d
    p := &_ui_arena[_ui_arena_n]
    _ui_arena_n += 1
    return p
}


ui_clay_color :: #force_inline proc(c: rl.Color) -> clay.Color {
    return { f32(c.r), f32(c.g), f32(c.b), f32(c.a) }
}


ui_hbar :: proc(id_base: string, ratio: f32, fill_col, bg_col: rl.Color, h: f32) {
    r := clamp(ratio, 0, 1)
    if clay.UI(clay.ID(id_base))({
        layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(h) } },
        backgroundColor = ui_clay_color(bg_col),
        cornerRadius    = clay.CornerRadiusAll(h * 0.3),
    }) {
        if r > 0 {
            fill_id := fmt.tprintf("%sFill", id_base)
            if clay.UI(clay.ID(fill_id))({
                layout          = { sizing = { clay.SizingPercent(r), clay.SizingGrow() } },
                backgroundColor = ui_clay_color(fill_col),
                cornerRadius    = clay.CornerRadiusAll(h * 0.3),
            }) {}
        }
    }
}


ui_spacer :: proc(id: string, h: f32) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(h) } },
    }) {}
}


ui_spacer_w :: proc(id: string, w: f32) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingFixed(w), clay.SizingGrow() } },
    }) {}
}


ui_divider :: proc(id: string) {
    if clay.UI(clay.ID(id))({
        layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(1) } },
        backgroundColor = ui_clay_color(COL_RULE),
    }) {}
}


ui_label :: proc(id, text: string, fs: f32, col: rl.Color, spacing: f32 = 0.5) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingFit(), clay.SizingFit() } },
    }) {
        clay.TextDynamic(text, clay.TextConfig({
            fontSize      = u16(fs),
            textColor     = ui_clay_color(col),
            letterSpacing = u16(spacing * 10),
        }))
    }
}


ui_section :: proc(id, title: string, fs: f32 = 0) {
    actual_fs := uis(13) if fs <= 0 else fs
    if clay.UI(clay.ID(id))({
        layout = {
            sizing  = { clay.SizingGrow(), clay.SizingFit() },
            padding = { left = u16(uis(2)) },
        },
    }) {
        clay.TextDynamic(title, clay.TextConfig({
            fontSize      = u16(actual_fs),
            textColor     = ui_clay_color(COL_MUTED),
            letterSpacing = 10,
        }))
    }
}
