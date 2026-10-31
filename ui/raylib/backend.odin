package tormentas_mu_raylib

import mu "vendor:microui"
import rl "vendor:raylib"
import "core:strings"
import "core:unicode/utf8"

Backend :: struct {}

init :: proc(b: ^Backend, ctx: ^mu.Context) {
    mu.init(ctx)
    ctx.text_width = proc(font: mu.Font, text: string) -> i32 {
        return i32(rl.MeasureTextEx(rl.GetFontDefault(), strings.clone_to_cstring(text, context.temp_allocator), 16, 1).x)
    }
    ctx.text_height = proc(font: mu.Font) -> i32 { return 16 }
}

shutdown :: proc(b: ^Backend) {}

input :: proc(b: ^Backend, ctx: ^mu.Context) {
    pos := rl.GetMousePosition()
    mu.input_mouse_move(ctx, i32(pos.x), i32(pos.y))
    buttons := [3]rl.MouseButton{.LEFT, .RIGHT, .MIDDLE}
    for button, i in buttons {
        if rl.IsMouseButtonPressed(button) { mu.input_mouse_down(ctx, i32(pos.x), i32(pos.y), mu.Mouse(i)) }
        if rl.IsMouseButtonReleased(button) { mu.input_mouse_up(ctx, i32(pos.x), i32(pos.y), mu.Mouse(i)) }
    }
    wheel := rl.GetMouseWheelMoveV()
    mu.input_scroll(ctx, i32(-wheel.x * 30), i32(-wheel.y * 30))
    keys := [16]rl.KeyboardKey{.LEFT_SHIFT, .LEFT_CONTROL, .LEFT_ALT, .BACKSPACE, .DELETE, .ENTER, .LEFT, .RIGHT, .HOME, .END, .A, .X, .C, .V, .RIGHT_SHIFT, .RIGHT_CONTROL}
    mapped := [16]mu.Key{.SHIFT, .CTRL, .ALT, .BACKSPACE, .DELETE, .RETURN, .LEFT, .RIGHT, .HOME, .END, .A, .X, .C, .V, .SHIFT, .CTRL}
    for key, i in keys {
        if rl.IsKeyPressed(key) { mu.input_key_down(ctx, mapped[i]) }
        if rl.IsKeyReleased(key) { mu.input_key_up(ctx, mapped[i]) }
    }
    for cp := rl.GetCharPressed(); cp != 0; cp = rl.GetCharPressed() {
        bytes, n := utf8.encode_rune(rune(cp))
        mu.input_text(ctx, string(bytes[:n]))
    }
}

render :: proc(b: ^Backend, ctx: ^mu.Context) {
    clipped := false
    defer if clipped { rl.EndScissorMode() }
    command_ptr: ^mu.Command
    for command in mu.next_command_iterator(ctx, &command_ptr) {
        switch c in command {
        case ^mu.Command_Clip:
            if clipped { rl.EndScissorMode() }
            rl.BeginScissorMode(c.rect.x, c.rect.y, max(c.rect.w, 0), max(c.rect.h, 0))
            clipped = true
        case ^mu.Command_Rect:
            rl.DrawRectangle(c.rect.x, c.rect.y, c.rect.w, c.rect.h, {c.color.r, c.color.g, c.color.b, c.color.a})
        case ^mu.Command_Text:
            rl.DrawTextEx(rl.GetFontDefault(), strings.clone_to_cstring(c.str, context.temp_allocator), {f32(c.pos.x), f32(c.pos.y)}, 16, 1, {c.color.r, c.color.g, c.color.b, c.color.a})
        case ^mu.Command_Icon:
            glyph: cstring
            #partial switch c.id {
            case .CLOSE: glyph = "x"
            case .CHECK: glyph = "+"
            case .COLLAPSED: glyph = ">"
            case .EXPANDED: glyph = "v"
            case .RESIZE: glyph = "/"
            }
            if glyph != nil {
                rl.DrawText(glyph, c.rect.x + c.rect.w/2 - 4, c.rect.y + c.rect.h/2 - 8, 16, {c.color.r, c.color.g, c.color.b, c.color.a})
            }
        case ^mu.Command_Jump:
        }
    }
}
