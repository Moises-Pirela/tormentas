package main

// =============================================================================
// config.odin — Keybindings and persistent settings
//
// Bindings are split by InputMode so each mode owns exactly the keys it needs.
// Adding a new input mode in the future means:
//   1. Add a new XxxBinds struct with its fields.
//   2. Add it as a field in Bindings.
//   3. Add defaults in default_binds().
//   4. Add xxx_bind_rows() for the keybinds screen.
//   5. Add the section to _bind_section_y() / draw_keybinds_screen().
//
// JSON layout on disk:
//   { "gameplay": { "move_up": 87, … }, "ui": { "close_panel": 256 } }
// =============================================================================

import "core:encoding/json"
import "core:os"
import rl "vendor:raylib"

CONFIG_PATH :: "data/config.json"

// ---------------------------------------------------------------------------
// Per-mode bind structs
// ---------------------------------------------------------------------------

// GameplayBinds — keys consumed only while input_mode == .Gameplay.
GameplayBinds :: struct {
    move_up:        i32,  // W
    move_down:      i32,  // S
    move_left:      i32,  // A
    move_right:     i32,  // D
    reload:         i32,  // R
    dodge:          i32,  // Space
    skill1:         i32,  // Q
    skill2:         i32,  // E
    skill3:         i32,  // F
    skill4:         i32,  // G
    interact:       i32,  // E  — open shop / craft / use portal
    loot_filter:    i32,  // Z  — cycle loot rarity filter
    open_inventory: i32,  // I
    open_stats:     i32,  // C
    open_abilities: i32,  // A  — (future)
    pause:          i32,  // Escape — open PauseMenu
}

// UIBinds — keys consumed only while input_mode == .UI (a panel is open).
UIBinds :: struct {
    close_panel:     i32,  // Escape — close the active panel
    compare_tooltip: i32,  // Left Alt — show equipped item comparison
}

// Bindings is the top-level config container written to / read from disk.
// Each InputMode maps to exactly one sub-struct.
Bindings :: struct {
    language: u8,            // 0=EN 1=ES 2=PT — persisted as "language" in JSON
    gameplay: GameplayBinds,
    ui:       UIBinds,
}

// ---------------------------------------------------------------------------
// Counts (needed by the keybinds screen)
// ---------------------------------------------------------------------------

GAMEPLAY_BIND_COUNT :: 16
UI_BIND_COUNT       :: 2
TOTAL_BIND_COUNT    :: GAMEPLAY_BIND_COUNT + UI_BIND_COUNT

// ---------------------------------------------------------------------------
// Global and defaults
// ---------------------------------------------------------------------------

g_binds: Bindings

default_binds :: proc() -> Bindings {
    return Bindings{
        gameplay = GameplayBinds{
            move_up        = i32(rl.KeyboardKey.W),
            move_down      = i32(rl.KeyboardKey.S),
            move_left      = i32(rl.KeyboardKey.A),
            move_right     = i32(rl.KeyboardKey.D),
            reload         = i32(rl.KeyboardKey.R),
            dodge          = i32(rl.KeyboardKey.SPACE),
            skill1         = i32(rl.KeyboardKey.Q),
            skill2         = i32(rl.KeyboardKey.E),
            skill3         = i32(rl.KeyboardKey.F),
            skill4         = i32(rl.KeyboardKey.G),
            interact       = i32(rl.KeyboardKey.E),
            loot_filter    = i32(rl.KeyboardKey.Z),
            open_inventory = i32(rl.KeyboardKey.I),
            open_stats     = i32(rl.KeyboardKey.C),
            open_abilities = i32(rl.KeyboardKey.A),
            pause          = i32(rl.KeyboardKey.ESCAPE),
        },
        ui = UIBinds{
            close_panel     = i32(rl.KeyboardKey.ESCAPE),
            compare_tooltip = i32(rl.KeyboardKey.LEFT_ALT),
        },
    }
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

load_config :: proc() {
    g_binds = default_binds()
    data, ok := os.read_entire_file(CONFIG_PATH)
    if !ok { return }
    defer delete(data)
    json.unmarshal(data, &g_binds)
}

save_config :: proc() {
    opt := json.Marshal_Options{ pretty = true }
    data, err := json.marshal(g_binds, opt)
    if err != nil { return }
    defer delete(data)
    os.write_entire_file(CONFIG_PATH, data)
}

// ---------------------------------------------------------------------------
// Bind rows — one proc per mode, used by the keybinds screen
// ---------------------------------------------------------------------------

BindRow :: struct {
    label: cstring,
    ptr:   ^i32,
}

gameplay_bind_rows :: proc() -> [GAMEPLAY_BIND_COUNT]BindRow {
    return {
        { "Move Up",          &g_binds.gameplay.move_up        },
        { "Move Down",        &g_binds.gameplay.move_down      },
        { "Move Left",        &g_binds.gameplay.move_left      },
        { "Move Right",       &g_binds.gameplay.move_right     },
        { "Reload",           &g_binds.gameplay.reload         },
        { "Dodge / Dash",     &g_binds.gameplay.dodge          },
        { "Skill 1",          &g_binds.gameplay.skill1         },
        { "Skill 2",          &g_binds.gameplay.skill2         },
        { "Skill 3",          &g_binds.gameplay.skill3         },
        { "Skill 4",          &g_binds.gameplay.skill4         },
        { "Interact",         &g_binds.gameplay.interact       },
        { "Loot Filter",      &g_binds.gameplay.loot_filter    },
        { "Inventory",        &g_binds.gameplay.open_inventory },
        { "Stats",            &g_binds.gameplay.open_stats     },
        { "Abilities",        &g_binds.gameplay.open_abilities },
        { "Pause",            &g_binds.gameplay.pause          },
    }
}

ui_bind_rows :: proc() -> [UI_BIND_COUNT]BindRow {
    return {
        { "Close Panel",     &g_binds.ui.close_panel     },
        { "Compare Tooltip", &g_binds.ui.compare_tooltip },
    }
}

// all_bind_rows returns every rebindable row in section order
// (gameplay first, then ui).  The keybinds screen indexes into this flat
// array; sections are rendered with visual headers but no extra indices.
all_bind_rows :: proc() -> [TOTAL_BIND_COUNT]BindRow {
    g := gameplay_bind_rows()
    u := ui_bind_rows()
    out: [TOTAL_BIND_COUNT]BindRow
    for i in 0..<GAMEPLAY_BIND_COUNT { out[i]                        = g[i] }
    for i in 0..<UI_BIND_COUNT       { out[GAMEPLAY_BIND_COUNT + i]  = u[i] }
    return out
}

// ---------------------------------------------------------------------------
// key_name — display string for a keyboard key
// ---------------------------------------------------------------------------

key_name :: proc(k: rl.KeyboardKey, buf: []u8) -> cstring {
    s: string
    #partial switch k {
    case .A:             s = "A"
    case .B:             s = "B"
    case .C:             s = "C"
    case .D:             s = "D"
    case .E:             s = "E"
    case .F:             s = "F"
    case .G:             s = "G"
    case .H:             s = "H"
    case .I:             s = "I"
    case .J:             s = "J"
    case .K:             s = "K"
    case .L:             s = "L"
    case .M:             s = "M"
    case .N:             s = "N"
    case .O:             s = "O"
    case .P:             s = "P"
    case .Q:             s = "Q"
    case .R:             s = "R"
    case .S:             s = "S"
    case .T:             s = "T"
    case .U:             s = "U"
    case .V:             s = "V"
    case .W:             s = "W"
    case .X:             s = "X"
    case .Y:             s = "Y"
    case .Z:             s = "Z"
    case .ZERO:          s = "0"
    case .ONE:           s = "1"
    case .TWO:           s = "2"
    case .THREE:         s = "3"
    case .FOUR:          s = "4"
    case .FIVE:          s = "5"
    case .SIX:           s = "6"
    case .SEVEN:         s = "7"
    case .EIGHT:         s = "8"
    case .NINE:          s = "9"
    case .SPACE:         s = "Space"
    case .ENTER:         s = "Enter"
    case .ESCAPE:        s = "Escape"
    case .TAB:           s = "Tab"
    case .LEFT_SHIFT:    s = "L.Shift"
    case .RIGHT_SHIFT:   s = "R.Shift"
    case .LEFT_CONTROL:  s = "L.Ctrl"
    case .RIGHT_CONTROL: s = "R.Ctrl"
    case .LEFT_ALT:      s = "L.Alt"
    case .RIGHT_ALT:     s = "R.Alt"
    case .UP:            s = "Up"
    case .DOWN:          s = "Down"
    case .LEFT:          s = "Left"
    case .RIGHT:         s = "Right"
    case .F1:            s = "F1"
    case .F2:            s = "F2"
    case .F3:            s = "F3"
    case .F4:            s = "F4"
    case .F5:            s = "F5"
    case .F6:            s = "F6"
    case .F7:            s = "F7"
    case .F8:            s = "F8"
    case .F9:            s = "F9"
    case .F10:           s = "F10"
    case .F11:           s = "F11"
    case .F12:           s = "F12"
    case .BACKSPACE:     s = "Bksp"
    case .DELETE:        s = "Del"
    case .INSERT:        s = "Ins"
    case .HOME:          s = "Home"
    case .END:           s = "End"
    case .PAGE_UP:       s = "PgUp"
    case .PAGE_DOWN:     s = "PgDn"
    case .CAPS_LOCK:     s = "Caps"
    case .KP_0:          s = "Num0"
    case .KP_1:          s = "Num1"
    case .KP_2:          s = "Num2"
    case .KP_3:          s = "Num3"
    case .KP_4:          s = "Num4"
    case .KP_5:          s = "Num5"
    case .KP_6:          s = "Num6"
    case .KP_7:          s = "Num7"
    case .KP_8:          s = "Num8"
    case .KP_9:          s = "Num9"
    case .KP_ENTER:      s = "NumEnter"
    case .MINUS:         s = "-"
    case .EQUAL:         s = "="
    case .LEFT_BRACKET:  s = "["
    case .RIGHT_BRACKET: s = "]"
    case .SEMICOLON:     s = ";"
    case .APOSTROPHE:    s = "'"
    case .COMMA:         s = ","
    case .PERIOD:        s = "."
    case .SLASH:         s = "/"
    case .GRAVE:         s = "`"
    case:
        n := 0
        v := int(k)
        tmp: [8]u8
        if v == 0 {
            tmp[0] = '?'; n = 1
        } else {
            for v > 0 {
                tmp[n] = u8('0') + u8(v % 10)
                n += 1; v /= 10
            }
            for i in 0..<n/2 {
                tmp[i], tmp[n-1-i] = tmp[n-1-i], tmp[i]
            }
        }
        n2 := copy(buf, tmp[:n])
        if n2 < len(buf) { buf[n2] = 0 }
        return cstring(&buf[0])
    }
    n := copy(buf, s)
    if n < len(buf) { buf[n] = 0 }
    return cstring(&buf[0])
}
