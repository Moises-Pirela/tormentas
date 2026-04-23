package main

import "core:encoding/json"
import "core:os"
import rl "vendor:raylib"

CONFIG_PATH :: "data/config.json"

KeyBinds :: struct {
    move_up:        i32,
    move_down:      i32,
    move_left:      i32,
    move_right:     i32,
    reload:         i32,
    dodge:          i32,
    skill1:         i32,
    skill2:         i32,
    skill3:         i32,
    open_inventory: i32,
    open_stats:     i32,
    open_abilities: i32,
    pause:          i32,
    skill4:         i32,
}

default_binds :: proc() -> KeyBinds {
    return KeyBinds{
        move_up        = i32(rl.KeyboardKey.W),
        move_down      = i32(rl.KeyboardKey.S),
        move_left      = i32(rl.KeyboardKey.A),
        move_right     = i32(rl.KeyboardKey.D),
        reload         = i32(rl.KeyboardKey.R),
        dodge          = i32(rl.KeyboardKey.SPACE),
        skill1         = i32(rl.KeyboardKey.Q),
        skill2         = i32(rl.KeyboardKey.E),
        skill3         = i32(rl.KeyboardKey.F),
        open_inventory = i32(rl.KeyboardKey.I),
        open_stats     = i32(rl.KeyboardKey.C),
        open_abilities = i32(rl.KeyboardKey.A),
        pause          = i32(rl.KeyboardKey.ESCAPE),
        skill4         = i32(rl.KeyboardKey.G),
    }
}

g_binds: KeyBinds

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

key_name :: proc(k: rl.KeyboardKey, buf: []u8) -> cstring {
    s: string
    #partial switch k {
    case .A:            s = "A"
    case .B:            s = "B"
    case .C:            s = "C"
    case .D:            s = "D"
    case .E:            s = "E"
    case .F:            s = "F"
    case .G:            s = "G"
    case .H:            s = "H"
    case .I:            s = "I"
    case .J:            s = "J"
    case .K:            s = "K"
    case .L:            s = "L"
    case .M:            s = "M"
    case .N:            s = "N"
    case .O:            s = "O"
    case .P:            s = "P"
    case .Q:            s = "Q"
    case .R:            s = "R"
    case .S:            s = "S"
    case .T:            s = "T"
    case .U:            s = "U"
    case .V:            s = "V"
    case .W:            s = "W"
    case .X:            s = "X"
    case .Y:            s = "Y"
    case .Z:            s = "Z"
    case .ZERO:         s = "0"
    case .ONE:          s = "1"
    case .TWO:          s = "2"
    case .THREE:        s = "3"
    case .FOUR:         s = "4"
    case .FIVE:         s = "5"
    case .SIX:          s = "6"
    case .SEVEN:        s = "7"
    case .EIGHT:        s = "8"
    case .NINE:         s = "9"
    case .SPACE:        s = "Space"
    case .ENTER:        s = "Enter"
    case .ESCAPE:       s = "Escape"
    case .TAB:          s = "Tab"
    case .LEFT_SHIFT:   s = "L.Shift"
    case .RIGHT_SHIFT:  s = "R.Shift"
    case .LEFT_CONTROL: s = "L.Ctrl"
    case .RIGHT_CONTROL:s = "R.Ctrl"
    case .LEFT_ALT:     s = "L.Alt"
    case .RIGHT_ALT:    s = "R.Alt"
    case .UP:           s = "Up"
    case .DOWN:         s = "Down"
    case .LEFT:         s = "Left"
    case .RIGHT:        s = "Right"
    case .F1:           s = "F1"
    case .F2:           s = "F2"
    case .F3:           s = "F3"
    case .F4:           s = "F4"
    case .F5:           s = "F5"
    case .F6:           s = "F6"
    case .F7:           s = "F7"
    case .F8:           s = "F8"
    case .F9:           s = "F9"
    case .F10:          s = "F10"
    case .F11:          s = "F11"
    case .F12:          s = "F12"
    case .BACKSPACE:    s = "Bksp"
    case .DELETE:       s = "Del"
    case .INSERT:       s = "Ins"
    case .HOME:         s = "Home"
    case .END:          s = "End"
    case .PAGE_UP:      s = "PgUp"
    case .PAGE_DOWN:    s = "PgDn"
    case .CAPS_LOCK:    s = "Caps"
    case .KP_0:         s = "Num0"
    case .KP_1:         s = "Num1"
    case .KP_2:         s = "Num2"
    case .KP_3:         s = "Num3"
    case .KP_4:         s = "Num4"
    case .KP_5:         s = "Num5"
    case .KP_6:         s = "Num6"
    case .KP_7:         s = "Num7"
    case .KP_8:         s = "Num8"
    case .KP_9:         s = "Num9"
    case .KP_ENTER:     s = "NumEnter"
    case .MINUS:        s = "-"
    case .EQUAL:        s = "="
    case .LEFT_BRACKET: s = "["
    case .RIGHT_BRACKET:s = "]"
    case .SEMICOLON:    s = ";"
    case .APOSTROPHE:   s = "'"
    case .COMMA:        s = ","
    case .PERIOD:       s = "."
    case .SLASH:        s = "/"
    case .GRAVE:        s = "`"
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

BIND_ROW_COUNT :: 14
bind_rows :: proc() -> [BIND_ROW_COUNT]struct{ label: cstring, ptr: ^i32 } {
    return {
        { "Move Up",          &g_binds.move_up        },
        { "Move Down",        &g_binds.move_down       },
        { "Move Left",        &g_binds.move_left       },
        { "Move Right",       &g_binds.move_right      },
        { "Reload",           &g_binds.reload          },
        { "Dodge / Dash",     &g_binds.dodge           },
        { "Skill 1",          &g_binds.skill1          },
        { "Skill 2",          &g_binds.skill2          },
        { "Skill 3",          &g_binds.skill3          },
        { "Skill 4",          &g_binds.skill4          },
        { "Inventory",        &g_binds.open_inventory  },
        { "Stats",            &g_binds.open_stats      },
        { "Abilities",        &g_binds.open_abilities  },
        { "Pause",            &g_binds.pause           },
    }
}
