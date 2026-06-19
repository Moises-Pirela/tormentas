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


// ui_grow is a flexible spacer that expands to fill remaining space on both axes.
// Use inside an hstack/vstack to push siblings apart. Self-contained (safe as a child).
ui_grow :: proc(id: string) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingGrow(), clay.SizingGrow() } },
    }) {}
}


// ui_dot draws a small filled circle (rounded square) — e.g. a presence indicator.
ui_dot :: proc(id: string, col: rl.Color, d: f32) {
    if clay.UI(clay.ID(id))({
        layout          = { sizing = { clay.SizingFixed(d), clay.SizingFixed(d) } },
        backgroundColor = ui_clay_color(col),
        cornerRadius    = clay.CornerRadiusAll(d * 0.5),
    }) {}
}


// ui_box draws a fixed-size filled rectangle — e.g. an icon placeholder slot.
ui_box :: proc(id: string, w, h: f32, col: rl.Color, radius: f32 = 0) {
    if clay.UI(clay.ID(id))({
        layout          = { sizing = { clay.SizingFixed(w), clay.SizingFixed(h) } },
        backgroundColor = ui_clay_color(col),
        cornerRadius    = clay.CornerRadiusAll(radius),
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
            fontId        = FONT_ID_BODY,
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
            fontId        = FONT_ID_BODY,
            fontSize      = u16(actual_fs),
            textColor     = ui_clay_color(COL_MUTED),
            letterSpacing = 10,
        }))
    }
}


// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

UIButtonVariant :: enum { Default, Primary, Danger }

// ui_button renders a fixed-size clickable button. Returns true the frame the
// mouse button is released over it. Call outside of any begin/end block — it
// is a self-contained Clay element.
ui_button :: proc(id, label: string, w, h: f32, variant := UIButtonVariant.Default) -> bool {
    btn_id  := clay.ID(id)
    hovered := clay.PointerOver(btn_id)
    clicked := hovered && rl.IsMouseButtonReleased(.LEFT)

    bg_col, bdr_col, lbl_col: rl.Color
    switch variant {
    case .Default:
        bg_col  = rl.Color{  28, 20, 10, 255 } if hovered else rl.Color{  12,  9,  6, 230 }
        bdr_col = COL_BRASS
        lbl_col = COL_PARCH if hovered else COL_MUTED
    case .Primary:
        bg_col  = rl.Color{ 210, 168, 65, 255 } if hovered else COL_BRASS
        bdr_col = rl.Color{ 240, 210, 100, 255 }
        lbl_col = rl.Color{ 10, 6, 2, 255 }
    case .Danger:
        bg_col  = COL_CRIMSON if hovered else rl.Color{ 90, 18, 14, 220 }
        bdr_col = COL_CRIMSON
        lbl_col = COL_PARCH
    }

    if clay.UI(btn_id)({
        layout = {
            sizing         = { clay.SizingFixed(w), clay.SizingFixed(h) },
            childAlignment = { x = .Center, y = .Center },
        },
        backgroundColor = ui_clay_color(bg_col),
        cornerRadius    = clay.CornerRadiusAll(3),
        border          = { color = ui_clay_color(bdr_col), width = { 1, 1, 1, 1, 0 } },
    }) {
        clay.TextDynamic(label, clay.TextConfig({
            fontId    = FONT_ID_BODY,
            fontSize  = u16(uis(12)),
            textColor = ui_clay_color(lbl_col),
        }))
    }
    return clicked
}

// ui_selectable is like ui_button but renders a persistent highlight when
// selected=true. Returns true when clicked.
ui_selectable :: proc(id, label: string, w, h: f32, selected: bool) -> bool {
    btn_id  := clay.ID(id)
    hovered := clay.PointerOver(btn_id)
    clicked := hovered && rl.IsMouseButtonReleased(.LEFT)

    bg_col  := rl.Color{ 45, 34, 16, 255 } if selected else (rl.Color{ 28, 20, 10, 240 } if hovered else rl.Color{ 12, 9, 6, 220 })
    bdr_col := COL_BRASS if (selected || hovered) else COL_RULE
    lbl_col := COL_PARCH if (selected || hovered) else COL_MUTED

    if clay.UI(btn_id)({
        layout = {
            sizing         = { clay.SizingFixed(w), clay.SizingFixed(h) },
            childAlignment = { x = .Center, y = .Center },
        },
        backgroundColor = ui_clay_color(bg_col),
        cornerRadius    = clay.CornerRadiusAll(3),
        border          = { color = ui_clay_color(bdr_col), width = { 1, 1, 1, 1, 0 } },
    }) {
        clay.TextDynamic(label, clay.TextConfig({
            fontId    = FONT_ID_BODY,
            fontSize  = u16(uis(12)),
            textColor = ui_clay_color(lbl_col),
        }))
    }
    return clicked
}


// ---------------------------------------------------------------------------
// Composite atomic elements
// ---------------------------------------------------------------------------

// ui_text_row draws a full-width row with a muted label on the left and a
// parchment-colored value on the right, separated by a grow spacer.
ui_text_row :: proc(base_id, label, value: string, fs: f32 = 0) {
    actual_fs := uis(12) if fs <= 0 else fs
    lbl_id    := fmt.tprintf("%sLbl", base_id)
    spc_id    := fmt.tprintf("%sSpc", base_id)
    val_id    := fmt.tprintf("%sVal", base_id)
    if clay.UI(clay.ID(base_id))({
        layout = {
            layoutDirection = .LeftToRight,
            childAlignment  = { y = .Center },
            sizing          = { clay.SizingGrow(), clay.SizingFit() },
        },
    }) {
        if clay.UI(clay.ID(lbl_id))({ layout = { sizing = { clay.SizingFit(), clay.SizingFit() } } }) {
            clay.TextDynamic(label, clay.TextConfig({
                fontId    = FONT_ID_BODY,
                fontSize  = u16(actual_fs),
                textColor = ui_clay_color(COL_MUTED),
            }))
        }
        // grow spacer pushes value to the right
        if clay.UI(clay.ID(spc_id))({ layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(1) } } }) {}
        if clay.UI(clay.ID(val_id))({ layout = { sizing = { clay.SizingFit(), clay.SizingFit() } } }) {
            clay.TextDynamic(value, clay.TextConfig({
                fontId    = FONT_ID_BODY,
                fontSize  = u16(actual_fs),
                textColor = ui_clay_color(COL_PARCH),
            }))
        }
    }
}

// ui_badge draws a small colored pill — fixed height, fit width.
ui_badge :: proc(id, text: string, bg_col: rl.Color) {
    pad := u16(uis(4))
    h   := uis(18)
    if clay.UI(clay.ID(id))({
        layout = {
            sizing         = { clay.SizingFit(), clay.SizingFixed(h) },
            padding        = { left = pad, right = pad },
            childAlignment = { x = .Center, y = .Center },
        },
        backgroundColor = ui_clay_color(bg_col),
        cornerRadius    = clay.CornerRadiusAll(h * 0.45),
    }) {
        clay.TextDynamic(text, clay.TextConfig({
            fontId    = FONT_ID_BODY,
            fontSize  = u16(uis(10)),
            textColor = ui_clay_color(COL_PARCH),
        }))
    }
}


// ---------------------------------------------------------------------------
// Container begin/end (use clay._OpenElementWithId + _CloseElement directly
// because the @(deferred_none) on clay.UI fires at the wrapper's scope exit,
// not the caller's — so containers MUST use the manual lifecycle API)
// ---------------------------------------------------------------------------

// ui_hstack_begin opens a horizontal child stack. Always pair with ui_hstack_end.
// Idiom: `ui_hstack_begin(...); defer ui_hstack_end()`
ui_hstack_begin :: proc(id: string, gap: u16 = 0, padding: u16 = 0,
                        align_y: clay.LayoutAlignmentY = .Center) {
    clay._OpenElementWithId(clay.ID(id))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .LeftToRight,
            childGap        = gap,
            padding         = clay.PaddingAll(padding),
            childAlignment  = { y = align_y },
            sizing          = { clay.SizingGrow(), clay.SizingFit() },
        },
    })
}
ui_hstack_end :: proc() { clay._CloseElement() }

// ui_vstack_begin opens a vertical child stack. Always pair with ui_vstack_end.
ui_vstack_begin :: proc(id: string, gap: u16 = 0, padding: u16 = 0) {
    clay._OpenElementWithId(clay.ID(id))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            childGap        = gap,
            padding         = clay.PaddingAll(padding),
            sizing          = { clay.SizingGrow(), clay.SizingFit() },
        },
    })
}
ui_vstack_end :: proc() { clay._CloseElement() }

// ui_floating_begin opens a floating overlay panel anchored to the screen root.
// anchor controls both the element and parent attachment point.
// Always pair with ui_floating_end.
ui_floating_begin :: proc(id: string, w, h: f32,
                          anchor: clay.FloatingAttachPointType = .CenterCenter,
                          offset: clay.Vector2 = {}) {
    clay._OpenElementWithId(clay.ID(id))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            sizing          = { clay.SizingFixed(w), clay.SizingFixed(h) },
        },
        floating = {
            offset     = offset,
            attachment = { element = anchor, parent = anchor },
            attachTo   = .Root,
        },
        backgroundColor = ui_clay_color(COL_PANEL),
        cornerRadius    = clay.CornerRadiusAll(4),
        border          = { color = ui_clay_color(COL_RULE), width = { 1, 1, 1, 1, 0 } },
    })
}
ui_floating_end :: proc() { clay._CloseElement() }

// ui_scroll_begin opens a vertically-scrollable clip container. Pass w/h <= 0 to grow
// on that axis. The childOffset is driven by clay.UpdateScrollContainers (wired in
// update_clay_input), so the host panel must redraw every frame for wheel scrolling
// to show (see the always-dirty group in ui_update). Pair with ui_scroll_end.
ui_scroll_begin :: proc(id: string, w: f32 = 0, h: f32 = 0) {
    clay._OpenElementWithId(clay.ID(id))
    wsz := clay.SizingGrow() if w <= 0 else clay.SizingFixed(w)
    hsz := clay.SizingGrow() if h <= 0 else clay.SizingFixed(h)
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            sizing          = { wsz, hsz },
        },
        clip   = { vertical = true, childOffset = clay.GetScrollOffset() },
    })
}
ui_scroll_end :: proc() { clay._CloseElement() }

// ui_tab draws a tab button that shows an active state. Returns true when clicked.
// accent tints the border when active/hovered; active_bg (zero => brass default) is
// the fill when active.
ui_tab :: proc(id, label: string, w, h: f32, active: bool, accent := COL_BRASS, active_bg := rl.Color{}) -> bool {
    tid     := clay.ID(id)
    hovered := clay.PointerOver(tid)
    clicked := hovered && rl.IsMouseButtonReleased(.LEFT)

    abg := active_bg
    if abg.a == 0 { abg = rl.Color{ 50, 38, 14, 245 } }
    bg := abg if active else (rl.Color{ 28, 20, 10, 230 } if hovered else rl.Color{ 16, 12, 8, 210 })
    bd := accent if (active || hovered) else COL_RULE
    tcol := COL_PARCH if (active || hovered) else COL_MUTED

    if clay.UI(tid)({
        layout = {
            sizing         = { clay.SizingFixed(w), clay.SizingFixed(h) },
            childAlignment = { x = .Center, y = .Center },
        },
        backgroundColor = ui_clay_color(bg),
        cornerRadius    = clay.CornerRadiusAll(4),
        border          = { color = ui_clay_color(bd), width = { 1, 1, 1, 1, 0 } },
    }) {
        clay.TextDynamic(label, clay.TextConfig({
            fontId    = FONT_ID_BODY,
            fontSize  = u16(uis(11)),
            textColor = ui_clay_color(tcol),
        }))
    }
    return clicked
}


// ---------------------------------------------------------------------------
// Composite panels
// ---------------------------------------------------------------------------

// ui_scrim draws a fullscreen dim behind a modal panel. Raw Raylib (not Clay).
ui_scrim :: proc(a: u8) {
    rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{ 0, 0, 0, a })
}

UIPanelStyle :: struct {
    bg_col:     rl.Color,                        // zero => COL_PANEL
    border_col: rl.Color,                        // zero => COL_BRASS
    accent_col: rl.Color,                        // zero => COL_BRASS
    title_col:  rl.Color,                        // zero => COL_PARCH
    title_fs:   f32,                             // <=0  => uis(16)
    anchor:     clay.FloatingAttachPointType,    // default .CenterCenter (enum 0 is .LeftTop, so set explicitly)
    offset:     clay.Vector2,
}

// ui_panel_begin opens a titled floating panel: accent top bar + centered title +
// divider, then leaves a padded vertical body column open for the caller. Pair with
// ui_panel_end. The accent bar and title use the manual lifecycle API on purpose —
// clay.UI's deferred close would fire at this proc's scope exit and mis-nest the body.
ui_panel_begin :: proc(id, title: string, w, h: f32, style := UIPanelStyle{}) {
    bg     := style.bg_col;     if bg.a == 0     { bg = COL_PANEL }
    border := style.border_col; if border.a == 0 { border = COL_BRASS }
    accent := style.accent_col; if accent.a == 0 { accent = COL_BRASS }
    tcol   := style.title_col;  if tcol.a == 0   { tcol = COL_PARCH }
    tfs    := style.title_fs;   if tfs <= 0      { tfs = uis(16) }

    // outer floating container — no padding so the accent bar sits flush at the top
    clay._OpenElementWithId(clay.ID(id))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            sizing          = { clay.SizingFixed(w), clay.SizingFixed(h) },
        },
        floating = {
            offset     = style.offset,
            attachment = { element = style.anchor, parent = style.anchor },
            attachTo   = .Root,
        },
        backgroundColor = ui_clay_color(bg),
        cornerRadius    = clay.CornerRadiusAll(5),
        border          = { color = ui_clay_color(border), width = { 1, 1, 1, 1, 0 } },
    })

    // accent top bar (manual open/close)
    clay._OpenElementWithId(clay.ID(fmt.tprintf("%sAccent", id)))
    clay.ConfigureOpenElement({
        layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(uis(3)) } },
        backgroundColor = ui_clay_color(accent),
    })
    clay._CloseElement()

    // padded body column — left open for the caller
    clay._OpenElementWithId(clay.ID(fmt.tprintf("%sBody", id)))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            childGap        = u16(uis(8)),
            padding         = clay.PaddingAll(u16(uis(14))),
            sizing          = { clay.SizingGrow(), clay.SizingGrow() },
        },
    })

    // centered title (manual open/close; text is a leaf)
    clay._OpenElementWithId(clay.ID(fmt.tprintf("%sTitle", id)))
    clay.ConfigureOpenElement({
        layout = {
            sizing         = { clay.SizingGrow(), clay.SizingFit() },
            childAlignment = { x = .Center },
        },
    })
    clay.TextDynamic(title, clay.TextConfig({
        fontId    = FONT_ID_TITLE,
        fontSize  = u16(tfs),
        textColor = ui_clay_color(tcol),
    }))
    clay._CloseElement()

    ui_divider(fmt.tprintf("%sDiv", id))
}

// ui_panel_end closes the body column and the outer floating container.
ui_panel_end :: proc() {
    clay._CloseElement()  // body
    clay._CloseElement()  // outer
}

// ui_clickable_begin opens a styled, full-width clickable row container and returns
// whether the pointer is over it. Pair with ui_clickable_end. Lay out the row's
// children (via helper procs) between them, then compute the click after closing:
//   hovered := ui_clickable_begin("Row", h); { ...children... }; ui_clickable_end()
//   if hovered && rl.IsMouseButtonReleased(.LEFT) { ... }
// accent tints the border/highlight when hovered.
ui_clickable_begin :: proc(id: string, h: f32, accent := COL_BRASS, active := false) -> (hovered: bool) {
    rid := clay.ID(id)
    hovered = clay.PointerOver(rid)
    bg  := rl.Color{ 50, 38, 14, 235 } if active else (rl.Color{ 30, 24, 14, 235 } if hovered else rl.Color{ 13, 10, 7, 210 })
    bdr := accent if (active || hovered) else COL_RULE
    clay._OpenElementWithId(rid)
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .LeftToRight,
            childGap        = u16(uis(10)),
            padding         = clay.PaddingAll(u16(uis(8))),
            childAlignment  = { y = .Center },
            sizing          = { clay.SizingGrow(), clay.SizingFixed(h) },
        },
        backgroundColor = ui_clay_color(bg),
        cornerRadius    = clay.CornerRadiusAll(3),
        border          = { color = ui_clay_color(bdr), width = { 1, 1, 1, 1, 0 } },
    })
    return
}
ui_clickable_end :: proc() { clay._CloseElement() }

// ui_card_begin opens a non-interactive, padded, bordered card container (vertical).
// Grows to fill width, fits its content height. Pair with ui_card_end.
ui_card_begin :: proc(id: string, bg, border_col: rl.Color, gap: u16 = 0) {
    clay._OpenElementWithId(clay.ID(id))
    clay.ConfigureOpenElement({
        layout = {
            layoutDirection = .TopToBottom,
            childGap        = gap,
            padding         = clay.PaddingAll(u16(uis(10))),
            sizing          = { clay.SizingGrow(), clay.SizingFit() },
        },
        backgroundColor = ui_clay_color(bg),
        cornerRadius    = clay.CornerRadiusAll(3),
        border          = { color = ui_clay_color(border_col), width = { 1, 1, 1, 1, 0 } },
    })
}
ui_card_end :: proc() { clay._CloseElement() }


// ---------------------------------------------------------------------------
// Settings widgets
// ---------------------------------------------------------------------------

// ui_label_w is a fixed-width text cell (for column alignment).
ui_label_w :: proc(id, text: string, w, fs: f32, col: rl.Color) {
    if clay.UI(clay.ID(id))({
        layout = { sizing = { clay.SizingFixed(w), clay.SizingFit() } },
    }) {
        clay.TextDynamic(text, clay.TextConfig({
            fontId    = FONT_ID_BODY,
            fontSize  = u16(fs),
            textColor = ui_clay_color(col),
        }))
    }
}

// ui_button_centered draws a fixed-size button horizontally centered in its row.
ui_button_centered :: proc(id, label: string, w, h: f32, variant := UIButtonVariant.Default) -> bool {
    clicked: bool
    ui_hstack_begin(fmt.tprintf("%sCRow", id), 0, 0, .Center)
    ui_grow(fmt.tprintf("%sCL", id))
    clicked = ui_button(id, label, w, h, variant)
    ui_grow(fmt.tprintf("%sCR", id))
    ui_hstack_end()
    return clicked
}

// ui_stepper draws a centered header above a "< value >" row. Returns -1 / 0 / +1
// when the left / right arrow is clicked. When disabled, arrows render dimmed and
// never report a click.
ui_stepper :: proc(id, header, value: string, enabled := true) -> (delta: int) {
    arrow := uis(28)
    ui_vstack_begin(fmt.tprintf("%sWrap", id), u16(uis(2)))
    {
        // Header (centered)
        ui_hstack_begin(fmt.tprintf("%sHdrRow", id), 0, 0, .Center)
        ui_grow(fmt.tprintf("%sHdrL", id))
        ui_label(fmt.tprintf("%sHdr", id), header, uis(13), COL_MUTED)
        ui_grow(fmt.tprintf("%sHdrR", id))
        ui_hstack_end()

        // Arrows + value
        ui_hstack_begin(fmt.tprintf("%sRow", id), 0, 0, .Center)
        if enabled {
            if ui_button(fmt.tprintf("%sL", id), "<", arrow, arrow) { delta = -1 }
        } else {
            ui_box(fmt.tprintf("%sLd", id), arrow, arrow, rl.Color{ 16, 13, 10, 200 }, 3)
        }
        ui_grow(fmt.tprintf("%sVL", id))
        ui_label(fmt.tprintf("%sVal", id), value, uis(18),
            COL_PARCH if enabled else rl.Color{ 80, 72, 55, 140 })
        ui_grow(fmt.tprintf("%sVR", id))
        if enabled {
            if ui_button(fmt.tprintf("%sR", id), ">", arrow, arrow) { delta = 1 }
        } else {
            ui_box(fmt.tprintf("%sRd", id), arrow, arrow, rl.Color{ 16, 13, 10, 200 }, 3)
        }
        ui_hstack_end()
    }
    ui_vstack_end()
    return
}

// ui_slider draws a labelled drag bar with a percent readout. Returns the (possibly
// updated) value and whether it changed this frame. Drag works under render-texture
// caching because dragging moves the mouse (marking the panel dirty each frame).
ui_slider :: proc(id, label: string, value: f32, label_w: f32 = 0) -> (new_value: f32, changed: bool) {
    new_value = value
    track_id  := clay.ID(fmt.tprintf("%sTrack", id))

    // Input: drag against the previous frame's track box.
    if rl.IsMouseButtonDown(.LEFT) && clay.PointerOver(track_id) {
        el := clay.GetElementData(track_id)
        if el.found && el.boundingBox.width > 0 {
            bb := el.boundingBox
            nv := clamp((rl.GetMousePosition().x - bb.x) / bb.width, 0, 1)
            if nv != value { new_value = nv; changed = true }
        }
    }

    lw    := uis(58) if label_w <= 0 else label_w
    bar_h := uis(14)

    ui_hstack_begin(fmt.tprintf("%sRow", id), u16(uis(8)), 0, .Center)
    {
        ui_label_w(fmt.tprintf("%sLbl", id), label, lw, uis(13), COL_MUTED)

        // Track with a percent-width fill child (manual lifecycle for correct nesting).
        clay._OpenElementWithId(track_id)
        clay.ConfigureOpenElement({
            layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(bar_h) } },
            backgroundColor = ui_clay_color(rl.Color{ 18, 14, 10, 255 }),
            border          = { color = ui_clay_color(COL_RULE), width = { 1, 1, 1, 1, 0 } },
        })
        clay._OpenElementWithId(clay.ID(fmt.tprintf("%sFill", id)))
        clay.ConfigureOpenElement({
            layout          = { sizing = { clay.SizingPercent(clamp(new_value, 0, 1)), clay.SizingGrow() } },
            backgroundColor = ui_clay_color(COL_BRASS),
        })
        clay._CloseElement()
        clay._CloseElement()

        pct := fmt.tprintf("%d%%", int(new_value * 100 + 0.5))
        ui_label_w(fmt.tprintf("%sPct", id), pct, uis(46), uis(13), COL_PARCH)
    }
    ui_hstack_end()
    return
}

// ui_item_row is a clickable full-width row: blank icon slot + name (left) + value (right).
// Returns true when clicked. Caller may draw a texture over the icon slot by reading
// clay.GetElementData("<id>Icon") after EndLayout. Built for vendor/list panels.
ui_item_row :: proc(id, name, value: string, h: f32 = 0) -> bool {
    row_h   := uis(40) if h <= 0 else h
    row_id  := clay.ID(id)
    hovered := clay.PointerOver(row_id)
    clicked := hovered && rl.IsMouseButtonReleased(.LEFT)

    bg       := rl.Color{ 28, 20, 10, 235 } if hovered else rl.Color{ 14, 10, 7, 220 }
    bdr      := COL_BRASS if hovered else COL_RULE
    name_col := COL_PARCH if hovered else COL_MUTED

    if clay.UI(row_id)({
        layout = {
            layoutDirection = .LeftToRight,
            childGap        = u16(uis(8)),
            padding         = { left = u16(uis(6)), right = u16(uis(10)),
                                top  = u16(uis(4)), bottom = u16(uis(4)) },
            childAlignment  = { y = .Center },
            sizing          = { clay.SizingGrow(), clay.SizingFixed(row_h) },
        },
        backgroundColor = ui_clay_color(bg),
        cornerRadius    = clay.CornerRadiusAll(3),
        border          = { color = ui_clay_color(bdr), width = { 1, 1, 1, 1, 0 } },
    }) {
        icon_sz := row_h - uis(10)
        if clay.UI(clay.ID(fmt.tprintf("%sIcon", id)))({
            layout          = { sizing = { clay.SizingFixed(icon_sz), clay.SizingFixed(icon_sz) } },
            backgroundColor = ui_clay_color(rl.Color{ 8, 6, 4, 255 }),
            cornerRadius    = clay.CornerRadiusAll(2),
        }) {}
        if clay.UI(clay.ID(fmt.tprintf("%sName", id)))({ layout = { sizing = { clay.SizingFit(), clay.SizingFit() } } }) {
            clay.TextDynamic(name, clay.TextConfig({
                fontId = FONT_ID_BODY, fontSize = u16(uis(12)), textColor = ui_clay_color(name_col),
            }))
        }
        if clay.UI(clay.ID(fmt.tprintf("%sSpc", id)))({ layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(1) } } }) {}
        if clay.UI(clay.ID(fmt.tprintf("%sVal", id)))({ layout = { sizing = { clay.SizingFit(), clay.SizingFit() } } }) {
            clay.TextDynamic(value, clay.TextConfig({
                fontId = FONT_ID_BODY, fontSize = u16(uis(12)), textColor = ui_clay_color(COL_BRASS),
            }))
        }
    }
    return clicked
}
