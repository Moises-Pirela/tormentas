package main

import "core:fmt"
import rl "vendor:raylib"

WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720

COL_BG       :: rl.Color{ 9, 11, 13, 255 }
COL_PANEL    :: rl.Color{ 24, 28, 31, 255 }
COL_LINE     :: rl.Color{ 92, 105, 110, 255 }
COL_TEXT     :: rl.Color{ 222, 226, 218, 255 }
COL_MUTED    :: rl.Color{ 145, 154, 150, 255 }
COL_ACCENT   :: rl.Color{ 218, 164, 82, 255 }
COL_STRUCT   :: rl.Color{ 58, 67, 72, 255 }
COL_POSITIVE :: rl.Color{ 122, 190, 142, 255 }

draw_text :: proc(text: cstring, x, y, size: i32, color: rl.Color) {
    rl.DrawText(text, x, y, size, color)
}

draw_line_row :: proc(label, value: cstring, x, y: i32) {
    draw_text(label, x, y, 18, COL_MUTED)
    draw_text(value, x + 210, y, 18, COL_TEXT)
}

draw_window_background :: proc() {
    rl.ClearBackground(COL_BG)

    for i in 0..<9 {
        x := i32(80 + i * 140)
        rl.DrawRectangle(x, 0, 24, WINDOW_HEIGHT, COL_STRUCT)
        rl.DrawRectangle(x + 24, 0, 2, WINDOW_HEIGHT, COL_LINE)
    }

    rl.DrawRectangle(0, 0, WINDOW_WIDTH, 92, rl.Color{ 12, 14, 15, 245 })
    rl.DrawRectangle(0, 90, WINDOW_WIDTH, 2, COL_ACCENT)
}

draw_project_dashboard :: proc(project: ^Project_Seed) {
    draw_window_background()

    draw_text("MEGASTRUCTURE FPS", 40, 28, 28, COL_TEXT)
    draw_text("semantic prototype / generator trace", 42, 60, 16, COL_MUTED)
    draw_text("ESC closes", WINDOW_WIDTH - 130, 36, 16, COL_MUTED)

    panel_x := i32(40)
    panel_y := i32(128)
    panel_w := i32(560)
    panel_h := i32(500)
    rl.DrawRectangle(panel_x, panel_y, panel_w, panel_h, COL_PANEL)
    rl.DrawRectangleLines(panel_x, panel_y, panel_w, panel_h, COL_LINE)

    draw_text("PROJECT PRINCIPLES", panel_x + 24, panel_y + 24, 20, COL_ACCENT)

    seed_buf: [96]u8
    seed_text := fmt.bprintf(seed_buf[:95], "%d", project.seed)
    seed_buf[len(seed_text)] = 0
    draw_line_row("seed", cstring(&seed_buf[0]), panel_x + 24, panel_y + 70)

    for i in 0..<project.principle_count {
        row_y := panel_y + 112 + i32(i) * 34
        principle_buf: [96]u8
        principle_text := fmt.bprintf(principle_buf[:95], "%v", project.principles[i])
        principle_buf[len(principle_text)] = 0
        draw_text("-", panel_x + 28, row_y, 18, COL_POSITIVE)
        draw_text(cstring(&principle_buf[0]), panel_x + 54, row_y, 18, COL_TEXT)
    }

    region := project.regions[0]
    trace := generate_region_trace(region)

    detail_x := i32(640)
    detail_y := i32(128)
    detail_w := i32(600)
    detail_h := i32(500)
    rl.DrawRectangle(detail_x, detail_y, detail_w, detail_h, COL_PANEL)
    rl.DrawRectangleLines(detail_x, detail_y, detail_w, detail_h, COL_LINE)

    draw_text("ACTIVE REGION", detail_x + 24, detail_y + 24, 20, COL_ACCENT)

    region_name_buf: [128]u8
    region_name_text := fmt.bprintf(region_name_buf[:127], "%s", region.name)
    region_name_buf[len(region_name_text)] = 0
    draw_line_row("name", cstring(&region_name_buf[0]), detail_x + 24, detail_y + 70)

    purpose_buf: [96]u8
    purpose_text := fmt.bprintf(purpose_buf[:95], "%v", region.purpose)
    purpose_buf[len(purpose_text)] = 0
    draw_line_row("purpose", cstring(&purpose_buf[0]), detail_x + 24, detail_y + 104)

    scale_buf: [96]u8
    scale_text := fmt.bprintf(scale_buf[:95], "%v", region.scale)
    scale_buf[len(scale_text)] = 0
    draw_line_row("scale", cstring(&scale_buf[0]), detail_x + 24, detail_y + 138)

    rules_buf: [96]u8
    rules_text := fmt.bprintf(rules_buf[:95], "%d rules", trace.rule_count)
    rules_buf[len(rules_text)] = 0
    draw_line_row("generator", cstring(&rules_buf[0]), detail_x + 24, detail_y + 172)

    draw_text("TRACE", detail_x + 24, detail_y + 232, 20, COL_ACCENT)
    for i in 0..<trace.note_count {
        row_y := detail_y + 272 + i32(i) * 48
        draw_text("-", detail_x + 28, row_y, 18, COL_POSITIVE)

        note_buf: [256]u8
        note_text := fmt.bprintf(note_buf[:255], "%s", trace.notes[i])
        note_buf[len(note_text)] = 0
        draw_text(cstring(&note_buf[0]), detail_x + 54, row_y, 16, COL_TEXT)
    }
}

main :: proc() {
    project := make_project_seed(0x544F524D454E5441)
    dump_project_seed(&project)

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Megastructure FPS")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(.ESCAPE) {
            break
        }

        rl.BeginDrawing()
        draw_project_dashboard(&project)
        rl.EndDrawing()
    }
}
