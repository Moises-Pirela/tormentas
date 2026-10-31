package clockwork

import "core:fmt"
import "core:strings"

CONSOLE_LOG_MAX   :: 512
CONSOLE_MSG_LEN   :: 200
CONSOLE_INPUT_CAP :: 256
CONSOLE_HISTORY   :: 32
CONSOLE_SLIDE_SPD :: f32(12.0)
CONSOLE_SCROLL_AMT :: 3

LogLevel :: enum u8 {
	Info,
	Good,
	Warn,
	Error,
}

ConsoleLine :: struct {
	msg:   [CONSOLE_MSG_LEN]u8,
	len:   int,
	level: LogLevel,
}

CommandProc :: #type proc(c: ^Console, w: ^World, args: string)

Command :: struct {
	name: string,
	help: string,
	fn:   CommandProc,
}

Console :: struct {
	ring:          [CONSOLE_LOG_MAX]ConsoleLine,
	cursor:        int,
	count:         int,

	commands:      [dynamic]Command,

	input:         [CONSOLE_INPUT_CAP]u8,
	input_n:       int,

	history:       [CONSOLE_HISTORY][CONSOLE_INPUT_CAP]u8,
	history_len:   [CONSOLE_HISTORY]int,
	history_count: int,
	history_pick:  int,

	open:          bool,
	slide:         f32,
	scroll:        int,
}

console_destroy :: proc(c: ^Console) {
	delete(c.commands)
	c^ = {}
}

console_log :: proc(c: ^Console, msg: string) {console_push(c, msg, .Info)}
console_good :: proc(c: ^Console, msg: string) {console_push(c, msg, .Good)}
console_warn :: proc(c: ^Console, msg: string) {console_push(c, msg, .Warn)}
console_error :: proc(c: ^Console, msg: string) {console_push(c, msg, .Error)}

console_logf :: proc(c: ^Console, format: string, args: ..any) {
	console_push(c, fmt.tprintf(format, ..args), .Info)
}

console_goodf :: proc(c: ^Console, format: string, args: ..any) {
	console_push(c, fmt.tprintf(format, ..args), .Good)
}

console_warnf :: proc(c: ^Console, format: string, args: ..any) {
	console_push(c, fmt.tprintf(format, ..args), .Warn)
}

console_errorf :: proc(c: ^Console, format: string, args: ..any) {
	console_push(c, fmt.tprintf(format, ..args), .Error)
}

console_push :: proc(c: ^Console, msg: string, level: LogLevel) {
	e := &c.ring[c.cursor %% CONSOLE_LOG_MAX]
	n := min(len(msg), CONSOLE_MSG_LEN - 1)
	e.msg = {}
	copy(e.msg[:n], msg[:n])
	e.len = n
	e.level = level
	c.cursor += 1
	if c.count < CONSOLE_LOG_MAX {c.count += 1}
}

console_clear :: proc(c: ^Console) {
	c.cursor = 0
	c.count = 0
	c.scroll = 0
}

console_line :: proc(c: ^Console, back: int) -> (line: ^ConsoleLine, ok: bool) {
	if back < 0 || back >= c.count {return nil, false}
	return &c.ring[(c.cursor - 1 - back) %% CONSOLE_LOG_MAX], true
}

console_line_text :: proc(c: ^Console, back: int) -> (text: string, level: LogLevel, ok: bool) {
	e := console_line(c, back) or_return
	return string(e.msg[:e.len]), e.level, true
}

console_toggle :: proc(c: ^Console) {
	c.open = !c.open
	if c.open {
		c.input_n = 0
		c.scroll = 0
		c.history_pick = -1
	}
}

console_update :: proc(c: ^Console, dt: f32) {
	target := c.open ? f32(1) : f32(0)
	step := dt * CONSOLE_SLIDE_SPD
	if c.slide < target {
		c.slide = min(c.slide + step, target)
		return
	}
	c.slide = max(c.slide - step, target)
}

console_scroll_by :: proc(c: ^Console, lines: int, visible: int) {
	max_scroll := max(c.count - visible, 0)
	c.scroll = clamp(c.scroll + lines, 0, max_scroll)
}

console_text :: proc(c: ^Console) -> string {
	return string(c.input[:c.input_n])
}

console_input_char :: proc(c: ^Console, ch: u8) {
	if c.input_n >= CONSOLE_INPUT_CAP - 1 {return}
	if ch < 32 || ch > 126 {return}
	c.input[c.input_n] = ch
	c.input_n += 1
}

console_input_text :: proc(c: ^Console, s: string) {
	for i in 0 ..< len(s) {console_input_char(c, s[i])}
}

console_backspace :: proc(c: ^Console) {
	if c.input_n > 0 {c.input_n -= 1}
}

console_input_clear :: proc(c: ^Console) {
	c.input_n = 0
}

console_history_push :: proc(c: ^Console, line: string) {
	if len(line) == 0 {return}
	if c.history_count > 0 {
		prev := c.history_count - 1
		if string(c.history[prev %% CONSOLE_HISTORY][:c.history_len[prev %% CONSOLE_HISTORY]]) == line {
			c.history_pick = -1
			return
		}
	}
	slot := c.history_count %% CONSOLE_HISTORY
	n := min(len(line), CONSOLE_INPUT_CAP - 1)
	c.history[slot] = {}
	copy(c.history[slot][:n], line[:n])
	c.history_len[slot] = n
	c.history_count += 1
	c.history_pick = -1
}

console_history_step :: proc(c: ^Console, dir: int) {
	depth := min(c.history_count, CONSOLE_HISTORY)
	if depth == 0 {return}

	pick := c.history_pick + dir
	if pick < -1 {pick = -1}
	if pick >= depth {pick = depth - 1}
	c.history_pick = pick

	if pick < 0 {
		c.input_n = 0
		return
	}
	slot := (c.history_count - 1 - pick) %% CONSOLE_HISTORY
	n := c.history_len[slot]
	copy(c.input[:n], c.history[slot][:n])
	c.input_n = n
}

console_complete :: proc(c: ^Console) -> bool {
	prefix := console_text(c)
	if len(prefix) == 0 {return false}
	if strings.index_byte(prefix, ' ') >= 0 {return false}

	match: string
	hits := 0
	for cmd in c.commands {
		if !strings.has_prefix(cmd.name, prefix) {continue}
		hits += 1
		match = cmd.name
	}

	if hits == 1 {
		c.input_n = 0
		console_input_text(c, match)
		return true
	}
	if hits > 1 {
		console_logf(c, "-- %d matches --", hits)
		for cmd in c.commands {
			if strings.has_prefix(cmd.name, prefix) {
				console_logf(c, "  %-12s %s", cmd.name, cmd.help)
			}
		}
	}
	return false
}

console_register :: proc(c: ^Console, name, help: string, fn: CommandProc) {
	for &cmd in c.commands {
		if cmd.name == name {
			cmd.help = help
			cmd.fn = fn
			return
		}
	}
	append(&c.commands, Command{name = name, help = help, fn = fn})
}

console_find :: proc(c: ^Console, name: string) -> (cmd: ^Command, ok: bool) {
	for &entry in c.commands {
		if entry.name == name {return &entry, true}
	}
	return nil, false
}

console_submit :: proc(c: ^Console, w: ^World) {
	line := strings.clone(console_text(c), context.temp_allocator)
	c.input_n = 0
	if len(strings.trim_space(line)) == 0 {return}
	console_history_push(c, line)
	console_logf(c, "> %s", line)
	console_exec(c, w, line)
	c.scroll = 0
}

console_exec :: proc(c: ^Console, w: ^World, raw: string) {
	s := strings.trim_space(raw)
	if len(s) == 0 {return}

	name, args := console_split(s)
	cmd, ok := console_find(c, name)
	if !ok {
		console_errorf(c, "unknown command '%s' -- type 'help'", name)
		return
	}
	cmd.fn(c, w, args)
}

console_split :: proc(s: string) -> (head: string, rest: string) {
	i := strings.index_byte(s, ' ')
	if i < 0 {return s, ""}
	return s[:i], strings.trim_space(s[i + 1:])
}

console_arg :: proc(args: string) -> (head: string, rest: string) {
	return console_split(strings.trim_space(args))
}
