package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: strip_comments <file>...")
		os.exit(2)
	}

	total_before := 0
	total_after := 0
	for path in os.args[1:] {
		data, ok := os.read_entire_file(path)
		if !ok {
			fmt.eprintfln("cannot read %s", path)
			continue
		}
		defer delete(data)

		out := strip(string(data))
		defer delete(out)

		if !os.write_entire_file(path, transmute([]u8)out) {
			fmt.eprintfln("cannot write %s", path)
			continue
		}
		total_before += len(data)
		total_after += len(out)
		fmt.printfln("%-44s %7d -> %7d", path, len(data), len(out))
	}
	fmt.printfln("\ntotal %d -> %d bytes (%d removed)", total_before, total_after, total_before - total_after)
}

Span :: struct {
	lo: int,
	hi: int,
}

strip :: proc(src: string) -> string {
	b := strings.builder_make()
	raws := make([dynamic]Span, 0, 8)
	defer delete(raws)

	i := 0
	n := len(src)
	for i < n {
		ch := src[i]

		switch ch {
		case '"':
			strings.write_byte(&b, ch)
			i += 1
			for i < n {
				if src[i] == '\\' && i + 1 < n {
					strings.write_byte(&b, src[i])
					strings.write_byte(&b, src[i + 1])
					i += 2
					continue
				}
				strings.write_byte(&b, src[i])
				closed := src[i] == '"'
				i += 1
				if closed {break}
			}

		case '`':
			start := strings.builder_len(b)
			strings.write_byte(&b, ch)
			i += 1
			for i < n {
				strings.write_byte(&b, src[i])
				closed := src[i] == '`'
				i += 1
				if closed {break}
			}
			append(&raws, Span{start, strings.builder_len(b)})

		case '\'':
			strings.write_byte(&b, ch)
			i += 1
			for i < n {
				if src[i] == '\\' && i + 1 < n {
					strings.write_byte(&b, src[i])
					strings.write_byte(&b, src[i + 1])
					i += 2
					continue
				}
				strings.write_byte(&b, src[i])
				closed := src[i] == '\''
				i += 1
				if closed {break}
			}

		case '/':
			if i + 1 < n && src[i + 1] == '/' {
				for i < n && src[i] != '\n' {i += 1}
			} else if i + 1 < n && src[i + 1] == '*' {
				depth := 1
				i += 2
				for i < n && depth > 0 {
					if i + 1 < n && src[i] == '/' && src[i + 1] == '*' {
						depth += 1
						i += 2
						continue
					}
					if i + 1 < n && src[i] == '*' && src[i + 1] == '/' {
						depth -= 1
						i += 2
						continue
					}
					i += 1
				}
			} else {
				strings.write_byte(&b, ch)
				i += 1
			}

		case:
			strings.write_byte(&b, ch)
			i += 1
		}
	}

	stripped := strings.to_string(b)
	out := tidy(stripped, raws[:])
	strings.builder_destroy(&b)
	return out
}

tidy :: proc(src: string, raws: []Span) -> string {
	b := strings.builder_make()

	in_raw :: proc(raws: []Span, lo: int, hi: int) -> bool {
		for r in raws {
			if lo < r.hi && hi > r.lo {return true}
		}
		return false
	}

	Line :: struct {
		text: string,
		raw:  bool,
	}
	lines := make([dynamic]Line, 0, 512)
	defer delete(lines)

	at := 0
	for at <= len(src) {
		end := at
		for end < len(src) && src[end] != '\n' {end += 1}
		raw := in_raw(raws, at, end)
		text := raw ? src[at:end] : strings.trim_right_space(src[at:end])
		append(&lines, Line{text, raw})
		if end >= len(src) {break}
		at = end + 1
	}

	keep := make([dynamic]bool, len(lines))
	defer delete(keep)

	prev_real := -1
	for i in 0 ..< len(lines) {
		l := lines[i]
		if l.raw || len(l.text) != 0 {
			keep[i] = true
			prev_real = i
			continue
		}

		if prev_real < 0 {continue}
		if lines[prev_real].raw {
			keep[i] = true
			continue
		}
		if len(keep) > 0 && i > 0 && !lines[i - 1].raw && len(lines[i - 1].text) == 0 {continue}

		prev := strings.trim_space(lines[prev_real].text)
		if strings.has_suffix(prev, "{") || strings.has_suffix(prev, "(") {continue}

		next := -1
		for j in i + 1 ..< len(lines) {
			if lines[j].raw || len(lines[j].text) != 0 {
				next = j
				break
			}
		}
		if next < 0 {continue}
		nxt := strings.trim_space(lines[next].text)
		if strings.has_prefix(nxt, "}") || strings.has_prefix(nxt, ")") {continue}

		keep[i] = true
	}

	for i in 0 ..< len(lines) {
		if !keep[i] {continue}
		strings.write_string(&b, lines[i].text)
		strings.write_byte(&b, '\n')
	}

	res := strings.trim_right_space(strings.to_string(b))
	out := strings.concatenate({res, "\n"})
	strings.builder_destroy(&b)
	return out
}
