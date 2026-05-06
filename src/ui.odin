package main

// =============================================================================
// UI — shared framework for all Clay-based screens
//
//   Color palette        COL_* constants (canonical source for the whole pkg)
//   Custom draw types    UICustomData + frame arena (safe rawptr for Clay)
//   Clay helpers         ui_hbar, ui_spacer, ui_divider, ui_label, ui_section
//
// Every UI file (ui_hud, ui_inventory, ui_character) builds on top of this.
// =============================================================================

import rl   "vendor:raylib"
import clay "../clay"
import      "core:fmt"

// ── Color palette ─────────────────────────────────────────────────────────
// Moved here from render.odin so shop.odin / hub.odin / main_menu.odin
// continue to resolve them without any import changes (same package).

COL_PARCH   :: rl.Color{ 222, 207, 162, 245 }
COL_CRIMSON :: rl.Color{ 178,  40,  36, 255 }
COL_BRASS   :: rl.Color{ 188, 150,  55, 235 }
COL_MUTED   :: rl.Color{ 128, 118,  88, 195 }
COL_PANEL   :: rl.Color{  10,   7,   5, 210 }
COL_RULE    :: rl.Color{ 130, 100,  38, 150 }
COL_SHIELD  :: rl.Color{  80, 180, 255, 220 }
COL_STAT    :: rl.Color{ 140, 195, 235, 230 }
COL_AFFIX   :: rl.Color{ 195, 168,  72, 235 }

// ── Custom-draw type system ────────────────────────────────────────────────
// Clay emits a .Custom render command for any element whose
// custom.customData pointer is non-nil.  clay_renderer.odin dispatches on
// UICustomData.kind and calls the matching private draw proc.
//
// Instances live in a per-frame bump arena so there is no heap allocation.

UICustomKind :: enum u8 {
    None,
    Orb,         // HP / Energy globe with liquid fill + optional shield ring
    AbilityChip, // Q / E / F / G slot with cooldown overlay (HUD)
    AmmoChip,    // weapon ammo count and reload progress
    InvSlot,     // armor equip slot drawn in the inventory panel
    WeaponSlot,  // weapon / offhand box in the inventory panel
    InvAbility,  // ability slot inside the inventory panel
}

// UICustomOrb ─ circular globe drawn by _draw_orb in clay_renderer.odin
UICustomOrb :: struct {
    fill_ratio:   f32,        // 0–1, fraction of globe filled
    shield_ratio: f32,        // 0–1, arc drawn around the rim (0 = hidden)
    fill_col:     rl.Color,   // liquid colour
    bg_col:       rl.Color,   // empty part of globe
    value_text:   [8]u8,      // null-terminated current-value string e.g. "240"
}

// UICustomAbility ─ one ability chip drawn by _draw_ability_chip
UICustomAbility :: struct {
    cd_ratio:    f32,         // 1 = full cooldown, 0 = ready
    charge_glow: bool,        // DeathShot charging pulse
    dance_glow:  bool,        // DevilsDance ready pulse
    has_ability: bool,
    key_label:   [4]u8,       // "Q\0", "E\0", etc.
    name_label:  [24]u8,      // null-terminated short name
}

// UICustomAmmo ─ weapon ammo/reload chip drawn by _draw_ammo_chip
UICustomAmmo :: struct {
    ammo_ratio:   f32,        // current / max (0–1)
    reload_ratio: f32,        // reload progress (0–1); 0 = not reloading
    is_reloading: bool,
    is_melee:     bool,       // melee/infinite-ammo weapons skip the bar
    ammo_text:    [8]u8,      // "8", "R", "M" (null-terminated)
    wep_name:     [24]u8,     // null-terminated weapon display name
}

// UICustomInvSlot — armor equip slot (Head / Chest / Boots)
UICustomInvSlot :: struct {
    label:     [8]u8,    // "HEAD\0", "CHEST\0", "BOOTS\0"
    item_name: [24]u8,   // equipped item display name, or "empty\0"
    has_item:  bool,
    is_target: bool,     // golden highlight: valid drop target during drag
}

// UICustomWeaponSlot — weapon / offhand box
UICustomWeaponSlot :: struct {
    type_label: [12]u8,  // "WEAPON I\0", "OFFHAND MOD\0"
    item_name:  [24]u8,  // equipped item name, or "empty\0"
    has_item:   bool,
    is_blocked: bool,    // offhand locked by a two-handed primary
    is_target:  bool,
}

// UICustomInvAbility — ability slot shown in the inventory panel
UICustomInvAbility :: struct {
    key_label:  [4]u8,   // "Q\0", "E\0", etc.
    name:       [24]u8,  // ability display name, or "" when empty
    has_item:   bool,
    is_passive: bool,
    is_target:  bool,
    rarity_col: rl.Color,
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
    },
}

// ── Frame bump arena ──────────────────────────────────────────────────────
// Clay stores the rawptr from custom.customData without copying the payload.
// The pointer must remain valid until clay_raylib_render() finishes.
// This fixed arena satisfies that lifetime at zero allocation cost.
//
// Call ui_frame_reset() once before clay.BeginLayout() in each draw proc.

@(private = "file") _ui_arena:   [128]UICustomData
@(private = "file") _ui_arena_n: int

ui_frame_reset :: proc() {
    _ui_arena_n = 0
}

// ui_push_custom stores d in the arena and returns a stable rawptr.
ui_push_custom :: proc(d: UICustomData) -> rawptr {
    assert(_ui_arena_n < len(_ui_arena), "UICustomData frame arena overflow")
    _ui_arena[_ui_arena_n] = d
    p := &_ui_arena[_ui_arena_n]
    _ui_arena_n += 1
    return p
}

// ── Clay colour bridge ────────────────────────────────────────────────────

ui_clay_color :: #force_inline proc(c: rl.Color) -> clay.Color {
    return { f32(c.r), f32(c.g), f32(c.b), f32(c.a) }
}

// ── Layout helpers ────────────────────────────────────────────────────────
// Thin Clay wrappers that keep individual UI procs readable.
// All sizing and colour choices follow the game's design language.

// ui_hbar – horizontal progress bar built from two nested Clay elements.
// id_base is used for the track element; "<id_base>Fill" for the fill strip.
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

// ui_spacer – invisible fixed-height gap (for TopToBottom containers).
ui_spacer :: proc(id: string, h: f32) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(h) } },
    }) {}
}

// ui_spacer_w – invisible fixed-width gap (for LeftToRight containers).
ui_spacer_w :: proc(id: string, w: f32) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingFixed(w), clay.SizingGrow() } },
    }) {}
}

// ui_divider – 1-pixel horizontal rule.
ui_divider :: proc(id: string) {
    if clay.UI(clay.ID(id))({
        layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(1) } },
        backgroundColor = ui_clay_color(COL_RULE),
    }) {}
}

// ui_label – dynamic-text element sized to its content.
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

// ui_section – uppercase section-header label, left-padded.
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
