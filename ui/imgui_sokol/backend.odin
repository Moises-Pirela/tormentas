package tormentas_imgui_sokol

// Dear ImGui backend on gfx (docs/BACKEND_SWAP_PLAN.md §3.9). It replaces the raylib/rlgl one.
//
// Draw lists go through gfx's triangle stream, so they are recorded like any other drawing and end
// up in the right pass, in the main target, which also means screenshots include the dev tools.
// Input comes from gfx's per-frame state, so ImGui and the game always see the same pointer, keys
// and characters, including the tools probe's synthetic input.

import "core:os"
import "core:strings"

import im  "../../deps/imgui/imgui"
import gfx "../../src/gfx"

@(private = "file")
KeyMap :: struct { key: gfx.Key, im_key: im.Key }

@(private = "file")
KEY_MAP := [?]KeyMap{
    { .TAB, .Tab }, { .LEFT, .LeftArrow }, { .RIGHT, .RightArrow }, { .UP, .UpArrow }, { .DOWN, .DownArrow },
    { .PAGE_UP, .PageUp }, { .PAGE_DOWN, .PageDown }, { .HOME, .Home }, { .END, .End },
    { .INSERT, .Insert }, { .DELETE, .Delete }, { .BACKSPACE, .Backspace }, { .SPACE, .Space },
    { .ENTER, .Enter }, { .ESCAPE, .Escape },
    { .LEFT_CONTROL, .LeftCtrl }, { .LEFT_SHIFT, .LeftShift }, { .LEFT_ALT, .LeftAlt }, { .LEFT_SUPER, .LeftSuper },
    { .RIGHT_CONTROL, .RightCtrl }, { .RIGHT_SHIFT, .RightShift }, { .RIGHT_ALT, .RightAlt }, { .RIGHT_SUPER, .RightSuper },
    { .KB_MENU, .Menu },
    { .ZERO, ._0 }, { .ONE, ._1 }, { .TWO, ._2 }, { .THREE, ._3 }, { .FOUR, ._4 },
    { .FIVE, ._5 }, { .SIX, ._6 }, { .SEVEN, ._7 }, { .EIGHT, ._8 }, { .NINE, ._9 },
    { .A, .A }, { .B, .B }, { .C, .C }, { .D, .D }, { .E, .E }, { .F, .F }, { .G, .G }, { .H, .H },
    { .I, .I }, { .J, .J }, { .K, .K }, { .L, .L }, { .M, .M }, { .N, .N }, { .O, .O }, { .P, .P },
    { .Q, .Q }, { .R, .R }, { .S, .S }, { .T, .T }, { .U, .U }, { .V, .V }, { .W, .W }, { .X, .X },
    { .Y, .Y }, { .Z, .Z },
    { .F1, .F1 }, { .F2, .F2 }, { .F3, .F3 }, { .F4, .F4 }, { .F5, .F5 }, { .F6, .F6 },
    { .F7, .F7 }, { .F8, .F8 }, { .F9, .F9 }, { .F10, .F10 }, { .F11, .F11 }, { .F12, .F12 },
    { .APOSTROPHE, .Apostrophe }, { .COMMA, .Comma }, { .MINUS, .Minus }, { .PERIOD, .Period },
    { .SLASH, .Slash }, { .SEMICOLON, .Semicolon }, { .EQUAL, .Equal }, { .LEFT_BRACKET, .LeftBracket },
    { .BACKSLASH, .Backslash }, { .RIGHT_BRACKET, .RightBracket }, { .GRAVE, .GraveAccent },
    { .CAPS_LOCK, .CapsLock }, { .SCROLL_LOCK, .ScrollLock }, { .NUM_LOCK, .NumLock },
    { .PRINT_SCREEN, .PrintScreen }, { .PAUSE, .Pause },
    { .KP_0, .Keypad0 }, { .KP_1, .Keypad1 }, { .KP_2, .Keypad2 }, { .KP_3, .Keypad3 }, { .KP_4, .Keypad4 },
    { .KP_5, .Keypad5 }, { .KP_6, .Keypad6 }, { .KP_7, .Keypad7 }, { .KP_8, .Keypad8 }, { .KP_9, .Keypad9 },
    { .KP_DECIMAL, .KeypadDecimal }, { .KP_DIVIDE, .KeypadDivide }, { .KP_MULTIPLY, .KeypadMultiply },
    { .KP_SUBTRACT, .KeypadSubtract }, { .KP_ADD, .KeypadAdd }, { .KP_ENTER, .KeypadEnter }, { .KP_EQUAL, .KeypadEqual },
}

Backend :: struct {
    ctx:         ^im.Context,
    key_down:    [len(KEY_MAP)]bool,
    mods:        [4]bool,
    focused:     bool,
    last_cursor: im.MouseCursor,
    ini_path:    cstring,
    skip_chars:  [dynamic]rune,
}

@(private = "file") g_backend: ^Backend

// Textures ImGui refers to by id: its own atlases plus any game texture handed to texture_ref.
@(private = "file") g_textures: map[u32]gfx.Texture

@(private = "file")
_get_clipboard :: proc "c" (ctx: ^im.Context) -> cstring {
    return gfx.clipboard_text()
}

@(private = "file")
_set_clipboard :: proc "c" (ctx: ^im.Context, text: cstring) {
    gfx.set_clipboard_text(text)
}

init :: proc(b: ^Backend, ini_path: string, font_path: cstring, font_size: f32) {
    g_backend = b
    b.ctx = im.CreateContext()
    io := im.GetIO()
    io.ConfigFlags  += { .DockingEnable }
    io.BackendFlags += { .RendererHasTextures, .HasMouseCursors, .RendererHasVtxOffset }
    io.BackendPlatformName = "tormentas_sokol"
    io.BackendRendererName = "tormentas_sgl"
    io.ConfigWindowsMoveFromTitleBarOnly = true

    b.ini_path     = strings.clone_to_cstring(ini_path)
    io.IniFilename = b.ini_path

    pio := im.GetPlatformIO()
    pio.Platform_GetClipboardTextFn = _get_clipboard
    pio.Platform_SetClipboardTextFn = _set_clipboard
    pio.Renderer_TextureMaxWidth  = 8192
    pio.Renderer_TextureMaxHeight = 8192

    if font_path != nil && os.exists(string(font_path)) {
        im.FontAtlas_AddFontFromFileTTF(io.Fonts, font_path, font_size)
    }
    b.focused     = true
    b.last_cursor = .Arrow
}

shutdown :: proc(b: ^Backend) {
    if b.ctx == nil { return }
    pio := im.GetPlatformIO()
    for i in 0..<pio.Textures.Size {
        tex := ([^]^im.TextureData)(pio.Textures.Data)[i]
        if tex.RefCount == 1 { _destroy_texture(tex) }
    }
    im.DestroyContext(b.ctx)
    b.ctx = nil
    delete(b.ini_path)
    delete(b.skip_chars)
    delete(g_textures)
    g_textures = nil
    g_backend = nil
}

wants_mouse    :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantCaptureMouse }
wants_keyboard :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantCaptureKeyboard }
wants_text     :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantTextInput }

ignore_char_this_frame :: proc(b: ^Backend, r: rune) {
    append(&b.skip_chars, r)
}

// `mouse` is the pointer position in screen coordinates, passed in (gfx.mouse_position) so ImGui
// sees the same pointer as the game. When `real_input` is false (the tools probe's synthetic
// input), real keys, buttons, wheel and text are not forwarded.
new_frame :: proc(b: ^Backend, dt: f32, mouse: [2]f32, real_input := true) {
    io := im.GetIO()
    sw := f32(gfx.screen_width())
    sh := f32(gfx.screen_height())
    io.DisplaySize = { sw, sh }
    if sw > 0 && sh > 0 {
        io.DisplayFramebufferScale = { f32(gfx.render_width()) / sw, f32(gfx.render_height()) / sh }
    }
    io.DeltaTime = dt if dt > 0 else 1.0 / 60.0

    focused := gfx.window_focused()
    if focused != b.focused {
        im.IO_AddFocusEvent(io, focused)
        b.focused = focused
    }

    ctrl, shift, alt, super := gfx.key_modifiers()
    mods := [4]bool{ ctrl && real_input, shift && real_input, alt && real_input, super && real_input }
    MOD_KEYS := [4]im.Key{ .ImGuiMod_Ctrl, .ImGuiMod_Shift, .ImGuiMod_Alt, .ImGuiMod_Super }
    for i in 0..<4 {
        if mods[i] != b.mods[i] { im.IO_AddKeyEvent(io, MOD_KEYS[i], mods[i]) }
    }
    b.mods = mods

    for km, i in KEY_MAP {
        down := real_input && gfx.key_down(km.key)
        if down != b.key_down[i] {
            im.IO_AddKeyEvent(io, km.im_key, down)
            b.key_down[i] = down
        }
    }

    im.IO_AddMousePosEvent(io, mouse.x, mouse.y)
    BUTTONS := [3]gfx.MouseButton{ .LEFT, .RIGHT, .MIDDLE }
    for btn, i in BUTTONS {
        if !real_input { break }
        if gfx.mouse_pressed(btn)  { im.IO_AddMouseButtonEvent(io, i32(i), true) }
        if gfx.mouse_released(btn) { im.IO_AddMouseButtonEvent(io, i32(i), false) }
    }
    wheel := gfx.mouse_wheel_xy() if real_input else gfx.Vec2{}
    if wheel.x != 0 || wheel.y != 0 { im.IO_AddMouseWheelEvent(io, wheel.x, wheel.y) }

    if real_input && io.WantTextInput {
        for cp := gfx.char_pressed(); cp != 0; cp = gfx.char_pressed() {
            skip := false
            for s in b.skip_chars { if s == cp { skip = true; break } }
            if !skip { im.IO_AddInputCharacter(io, u32(cp)) }
        }
    }
    clear(&b.skip_chars)

    im.NewFrame()
}

@(private = "file")
_apply_cursor :: proc(b: ^Backend) {
    io := im.GetIO()
    if .NoMouseCursorChange in io.ConfigFlags { return }
    cursor := im.GetMouseCursor()
    if cursor == b.last_cursor { return }
    b.last_cursor = cursor
    #partial switch cursor {
    case .TextInput:  gfx.set_mouse_cursor(.Text)
    case .ResizeAll:  gfx.set_mouse_cursor(.Resize_All)
    case .ResizeNS:   gfx.set_mouse_cursor(.Resize_NS)
    case .ResizeEW:   gfx.set_mouse_cursor(.Resize_EW)
    case .ResizeNESW: gfx.set_mouse_cursor(.Resize_NESW)
    case .ResizeNWSE: gfx.set_mouse_cursor(.Resize_NWSE)
    case .Hand:       gfx.set_mouse_cursor(.Hand)
    case .NotAllowed: gfx.set_mouse_cursor(.Not_Allowed)
    case:             gfx.set_mouse_cursor(.Default)
    }
}

@(private = "file")
_destroy_texture :: proc(t: ^im.TextureData) {
    id := u32(im.TextureData_GetTexID(t))
    if tex, has := g_textures[id]; has {
        gfx.unload_texture(tex)
        delete_key(&g_textures, id)
    }
    im.TextureData_SetTexID(t, 0)
    im.TextureData_SetStatus(t, .Destroyed)
}

// ImGui owns its atlas pixels and tells us when to create or refresh the texture.
@(private = "file")
_update_texture :: proc(t: ^im.TextureData) {
    #partial switch t.Status {
    case .WantCreate:
        n := int(t.Width) * int(t.Height) * 4
        pixels := ([^]u8)(t.Pixels)[:n]
        tex := gfx.load_texture_pixels(pixels, t.Width, t.Height, .Bilinear)
        g_textures[tex.id] = tex
        im.TextureData_SetTexID(t, im.TextureID(tex.id))
        im.TextureData_SetStatus(t, .OK)
    case .WantUpdates:
        id := u32(im.TextureData_GetTexID(t))
        if tex, has := g_textures[id]; has {
            n := int(t.Width) * int(t.Height) * 4
            gfx.update_texture(tex, ([^]u8)(t.Pixels)[:n])
        }
        im.TextureData_SetStatus(t, .OK)
    case .WantDestroy:
        if t.UnusedFrames > 0 { _destroy_texture(t) }
    }
}

render :: proc(b: ^Backend) {
    im.Render()
    _apply_cursor(b)
    dd := im.GetDrawData()
    if dd == nil { return }

    if dd.Textures != nil {
        for i in 0..<dd.Textures.Size {
            t := ([^]^im.TextureData)(dd.Textures.Data)[i]
            if t.Status != .OK { _update_texture(t) }
        }
    }
    if dd.CmdListsCount == 0 { return }

    off := dd.DisplayPos
    for li in 0..<dd.CmdLists.Size {
        list := ([^]^im.DrawList)(dd.CmdLists.Data)[li]
        vtx  := list.VtxBuffer.Data
        idx  := list.IdxBuffer.Data
        for ci in 0..<list.CmdBuffer.Size {
            cmd := &([^]im.DrawCmd)(list.CmdBuffer.Data)[ci]
            if cmd.UserCallback != nil { continue }

            x0 := cmd.ClipRect.x - off.x
            y0 := cmd.ClipRect.y - off.y
            x1 := cmd.ClipRect.z - off.x
            y1 := cmd.ClipRect.w - off.y
            if x1 <= x0 || y1 <= y0 { continue }
            gfx.scissor_begin(i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))

            tex, has_tex := g_textures[u32(im.DrawCmd_GetTexID(cmd))]
            if has_tex { gfx.tris_begin_textured(tex) } else { gfx.tris_begin() }

            n := int(cmd.ElemCount)
            for e := 0; e < n; e += 1 {
                vi := u32(([^]im.DrawIdx)(idx)[int(cmd.IdxOffset) + e]) + cmd.VtxOffset
                v  := ([^]im.DrawVert)(vtx)[vi]
                col := gfx.Color{ u8(v.col), u8(v.col >> 8), u8(v.col >> 16), u8(v.col >> 24) }
                gfx.tri_vertex({ v.pos.x - off.x, v.pos.y - off.y }, { v.uv.x, v.uv.y }, col)
            }
            gfx.tris_end()
            gfx.scissor_end()
        }
    }
}

// Registers a game texture so ImGui can draw it (the anim editor's sprite previews).
texture_ref :: proc(t: gfx.Texture) -> im.TextureRef {
    if t.id != 0 { g_textures[t.id] = t }
    return im.TextureRef{ _TexID = im.TextureID(t.id) }
}
