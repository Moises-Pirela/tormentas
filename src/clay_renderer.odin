package main


import clay "../clay"
import rl   "vendor:raylib"
import      "core:math"
import      "core:strings"

clay_color :: #force_inline proc(c: clay.Color) -> rl.Color {
    return { u8(c[0]), u8(c[1]), u8(c[2]), u8(c[3]) }
}

clay_raylib_render :: proc(cmds: ^clay.ClayArray(clay.RenderCommand)) {
    for i in 0..<cmds.length {
        cmd := clay.RenderCommandArray_Get(cmds, i)
        bb  := cmd.boundingBox

        switch cmd.commandType {

        case .Rectangle:
            cfg := cmd.renderData.rectangle
            col := clay_color(cfg.backgroundColor)
            r   := cfg.cornerRadius.topLeft
            if r > 0 {
                radius := (r * 2) / min(bb.width, bb.height)
                rl.DrawRectangleRounded({ bb.x, bb.y, bb.width, bb.height }, radius, 8, col)
            } else {
                rl.DrawRectangle(
                    i32(math.round(bb.x)),
                    i32(math.round(bb.y)),
                    i32(math.round(bb.width)),
                    i32(math.round(bb.height)),
                    col)
            }

        case .Border:
            cfg := cmd.renderData.border
            col := clay_color(cfg.color)
            cr  := cfg.cornerRadius
            bw  := cfg.width
            if bw.left   > 0 { rl.DrawRectangle(i32(bb.x),                              i32(bb.y + cr.topLeft),    i32(bw.left),   i32(bb.height - cr.topLeft    - cr.bottomLeft),  col) }
            if bw.right  > 0 { rl.DrawRectangle(i32(bb.x + bb.width - f32(bw.right)),   i32(bb.y + cr.topRight),   i32(bw.right),  i32(bb.height - cr.topRight   - cr.bottomRight), col) }
            if bw.top    > 0 { rl.DrawRectangle(i32(bb.x + cr.topLeft),                 i32(bb.y),                 i32(bb.width  - cr.topLeft    - cr.topRight),   i32(bw.top),    col) }
            if bw.bottom > 0 { rl.DrawRectangle(i32(bb.x + cr.bottomLeft),              i32(bb.y + bb.height - f32(bw.bottom)), i32(bb.width - cr.bottomLeft - cr.bottomRight), i32(bw.bottom), col) }

        case .ScissorStart:
            rl.BeginScissorMode(
                i32(math.round(bb.x)),
                i32(math.round(bb.y)),
                i32(math.round(bb.width)),
                i32(math.round(bb.height)))

        case .ScissorEnd:
            rl.EndScissorMode()

        case .Text:
            cfg := cmd.renderData.text
            text := string(cfg.stringContents.chars[:cfg.stringContents.length])
            if len(text) == 0 { continue }
            fs := f32(cfg.fontSize)
            if fs <= 0 { fs = 12 }
            spacing := f32(cfg.letterSpacing)
            if spacing <= 0 { spacing = 0.5 }
            col := clay_color(cfg.textColor)

            line_start := 0
            line_idx := 0
            for i := 0; i <= len(text); i += 1 {
                if i < len(text) && text[i] != '\n' { continue }
                line := text[line_start:i]
                line_cs := strings.clone_to_cstring(line, context.temp_allocator)
                rl.DrawTextEx(g_font, line_cs, { bb.x, bb.y + f32(line_idx) * fs }, fs, spacing, col)
                line_start = i + 1
                line_idx += 1
            }
        case .Image: 
        case .Custom:
        case .None:
        }
    }
}
