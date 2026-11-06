package tormentas_imgui_raylib

import       "core:strings"
import im    "../../deps/imgui/imgui"
import rl    "vendor:raylib"
import rlgl  "vendor:raylib/rlgl"

@(private = "file")
KeyMap :: struct { rl_key: rl.KeyboardKey, im_key: im.Key }

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
    ctx:          ^im.Context,
    key_down:     [len(KEY_MAP)]bool,
    mods:         [4]bool,
    focused:      bool,
    last_cursor:  im.MouseCursor,
    ini_path:     cstring,
    clip_buf:     cstring,
    skip_chars:   [dynamic]rune,
}

@(private = "file") g_backend: ^Backend

@(private = "file")
_get_clipboard :: proc "c" (ctx: ^im.Context) -> cstring {
    return rl.GetClipboardText()
}

@(private = "file")
_set_clipboard :: proc "c" (ctx: ^im.Context, text: cstring) {
    rl.SetClipboardText(text)
}

init :: proc(b: ^Backend, ini_path: string, font_path: cstring, font_size: f32) {
    g_backend = b
    b.ctx = im.CreateContext()
    io := im.GetIO()
    io.ConfigFlags  += { .DockingEnable }
    io.BackendFlags += { .RendererHasTextures, .HasMouseCursors }
    io.BackendPlatformName = "tormentas_raylib"
    io.BackendRendererName = "tormentas_rlgl"
    io.ConfigWindowsMoveFromTitleBarOnly = true

    b.ini_path     = strings.clone_to_cstring(ini_path)
    io.IniFilename = b.ini_path

    pio := im.GetPlatformIO()
    pio.Platform_GetClipboardTextFn = _get_clipboard
    pio.Platform_SetClipboardTextFn = _set_clipboard
    pio.Renderer_TextureMaxWidth  = 8192
    pio.Renderer_TextureMaxHeight = 8192

    if font_path != nil && rl.FileExists(font_path) {
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
    g_backend = nil
}

wants_mouse    :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantCaptureMouse }
wants_keyboard :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantCaptureKeyboard }
wants_text     :: proc() -> bool { return im.GetCurrentContext() != nil && im.GetIO().WantTextInput }

ignore_char_this_frame :: proc(b: ^Backend, r: rune) {
    append(&b.skip_chars, r)
}

new_frame :: proc(b: ^Backend, dt: f32) {
    io := im.GetIO()
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    io.DisplaySize = { sw, sh }
    if sw > 0 && sh > 0 {
        io.DisplayFramebufferScale = { f32(rl.GetRenderWidth()) / sw, f32(rl.GetRenderHeight()) / sh }
    }
    io.DeltaTime = dt if dt > 0 else 1.0 / 60.0

    focused := rl.IsWindowFocused()
    if focused != b.focused {
        im.IO_AddFocusEvent(io, focused)
        b.focused = focused
    }

    mods := [4]bool{
        rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL),
        rl.IsKeyDown(.LEFT_SHIFT)   || rl.IsKeyDown(.RIGHT_SHIFT),
        rl.IsKeyDown(.LEFT_ALT)     || rl.IsKeyDown(.RIGHT_ALT),
        rl.IsKeyDown(.LEFT_SUPER)   || rl.IsKeyDown(.RIGHT_SUPER),
    }
    MOD_KEYS := [4]im.Key{ .ImGuiMod_Ctrl, .ImGuiMod_Shift, .ImGuiMod_Alt, .ImGuiMod_Super }
    for i in 0..<4 {
        if mods[i] != b.mods[i] { im.IO_AddKeyEvent(io, MOD_KEYS[i], mods[i]) }
    }
    b.mods = mods

    for km, i in KEY_MAP {
        down := rl.IsKeyDown(km.rl_key)
        if down != b.key_down[i] {
            im.IO_AddKeyEvent(io, km.im_key, down)
            b.key_down[i] = down
        }
    }

    mp := rl.GetMousePosition()
    im.IO_AddMousePosEvent(io, mp.x, mp.y)
    BUTTONS := [3]rl.MouseButton{ .LEFT, .RIGHT, .MIDDLE }
    for btn, i in BUTTONS {
        if rl.IsMouseButtonPressed(btn)  { im.IO_AddMouseButtonEvent(io, i32(i), true) }
        if rl.IsMouseButtonReleased(btn) { im.IO_AddMouseButtonEvent(io, i32(i), false) }
    }
    wheel := rl.GetMouseWheelMoveV()
    if wheel.x != 0 || wheel.y != 0 { im.IO_AddMouseWheelEvent(io, wheel.x, wheel.y) }

    if io.WantTextInput {
        for cp := rl.GetCharPressed(); cp != 0; cp = rl.GetCharPressed() {
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
    case .TextInput:  rl.SetMouseCursor(.IBEAM)
    case .ResizeAll:  rl.SetMouseCursor(.RESIZE_ALL)
    case .ResizeNS:   rl.SetMouseCursor(.RESIZE_NS)
    case .ResizeEW:   rl.SetMouseCursor(.RESIZE_EW)
    case .ResizeNESW: rl.SetMouseCursor(.RESIZE_NESW)
    case .ResizeNWSE: rl.SetMouseCursor(.RESIZE_NWSE)
    case .Hand:       rl.SetMouseCursor(.POINTING_HAND)
    case .NotAllowed: rl.SetMouseCursor(.NOT_ALLOWED)
    case:             rl.SetMouseCursor(.DEFAULT)
    }
}

TextureBox :: struct { tex: rl.Texture2D }

@(private = "file")
_destroy_texture :: proc(t: ^im.TextureData) {
    if t.BackendUserData != nil {
        box := (^TextureBox)(t.BackendUserData)
        rl.UnloadTexture(box.tex)
        free(box)
        t.BackendUserData = nil
    }
    im.TextureData_SetTexID(t, 0)
    im.TextureData_SetStatus(t, .Destroyed)
}

@(private = "file")
_update_texture :: proc(t: ^im.TextureData) {
    #partial switch t.Status {
    case .WantCreate:
        img := rl.Image{
            data    = t.Pixels,
            width   = t.Width,
            height  = t.Height,
            mipmaps = 1,
            format  = .UNCOMPRESSED_R8G8B8A8 if t.Format == .RGBA32 else .UNCOMPRESSED_GRAYSCALE,
        }
        box := new(TextureBox)
        box.tex = rl.LoadTextureFromImage(img)
        rl.SetTextureFilter(box.tex, .BILINEAR)
        t.BackendUserData = box
        im.TextureData_SetTexID(t, im.TextureID(box.tex.id))
        im.TextureData_SetStatus(t, .OK)
    case .WantUpdates:
        if t.BackendUserData != nil {
            box := (^TextureBox)(t.BackendUserData)
            rl.UpdateTexture(box.tex, t.Pixels)
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

    rlgl.DrawRenderBatchActive()
    rlgl.DisableBackfaceCulling()
    defer {
        rlgl.SetTexture(0)
        rlgl.EnableBackfaceCulling()
    }

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
            rl.BeginScissorMode(i32(x0), i32(y0), i32(x1 - x0), i32(y1 - y0))

            tex := u32(im.DrawCmd_GetTexID(cmd))
            if tex == 0 { tex = rlgl.GetTextureIdDefault() }

            n := int(cmd.ElemCount)
            for e := 0; e < n; e += 3 {
                rlgl.CheckRenderBatchLimit(3)
                rlgl.SetTexture(tex)
                rlgl.Begin(rlgl.TRIANGLES)
                for k in 0..<3 {
                    vi := u32(([^]im.DrawIdx)(idx)[int(cmd.IdxOffset) + e + k]) + cmd.VtxOffset
                    v  := ([^]im.DrawVert)(vtx)[vi]
                    rlgl.Color4ub(u8(v.col), u8(v.col >> 8), u8(v.col >> 16), u8(v.col >> 24))
                    rlgl.TexCoord2f(v.uv.x, v.uv.y)
                    rlgl.Vertex2f(v.pos.x - off.x, v.pos.y - off.y)
                }
                rlgl.End()
            }
            rl.EndScissorMode()
        }
    }
}

texture_ref :: proc(tex: rl.Texture2D) -> im.TextureRef {
    return im.TextureRef{ _TexID = im.TextureID(tex.id) }
}

