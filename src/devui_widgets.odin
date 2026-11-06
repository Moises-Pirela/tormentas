package main

import       "core:fmt"
import       "core:strings"
import ecs   "cw:clockwork"
import im    "../deps/imgui/imgui"

DEVUI_GOLD   :: im.Vec4{ 0.86, 0.68, 0.32, 1 }
DEVUI_GREEN  :: im.Vec4{ 0.45, 0.82, 0.45, 1 }
DEVUI_RED    :: im.Vec4{ 0.90, 0.40, 0.35, 1 }
DEVUI_MUTED  :: im.Vec4{ 0.58, 0.54, 0.46, 1 }

cs :: proc(s: string) -> cstring {
    return strings.clone_to_cstring(s, context.temp_allocator)
}

ui_text :: proc(format: string, args: ..any) {
    im.TextUnformatted(fmt.ctprintf(format, ..args))
}

ui_text_col :: proc(col: im.Vec4, format: string, args: ..any) {
    im.PushStyleColorImVec4(.Text, col)
    im.TextUnformatted(fmt.ctprintf(format, ..args))
    im.PopStyleColor()
}

ui_hint :: proc(format: string, args: ..any) {
    ui_text_col(DEVUI_MUTED, format, ..args)
}

ui_tooltip :: proc(format: string, args: ..any) {
    if im.BeginItemTooltip() {
        im.TextUnformatted(fmt.ctprintf(format, ..args))
        im.EndTooltip()
    }
}

ui_input_buf :: proc(label: cstring, buf: []u8, n: ^int, flags: im.InputTextFlags = {}, hint: cstring = nil) -> bool {
    if len(buf) == 0 { return false }
    n^ = clamp(n^, 0, len(buf) - 1)
    buf[n^] = 0
    changed: bool
    if hint != nil {
        changed = im.InputTextWithHint(label, hint, cstring(&buf[0]), uint(len(buf)), flags)
    } else {
        changed = im.InputText(label, cstring(&buf[0]), uint(len(buf)), flags)
    }
    n^ = len(string(cstring(&buf[0])))
    return changed
}

ui_input_i32 :: proc(label: cstring, v: ^int, lo, hi: int, step := 1) -> bool {
    x := i32(v^)
    if !im.InputInt(label, &x, i32(step), i32(step) * 10) { return false }
    x = clamp(x, i32(lo), i32(hi))
    if int(x) == v^ { return false }
    v^ = int(x)
    return true
}

ui_input_u8 :: proc(label: cstring, v: ^u8, lo, hi: u8) -> bool {
    x := int(v^)
    if !ui_input_i32(label, &x, int(lo), int(hi)) { return false }
    v^ = u8(x)
    return true
}

ui_input_u16 :: proc(label: cstring, v: ^u16, lo, hi: u16) -> bool {
    x := int(v^)
    if !ui_input_i32(label, &x, int(lo), int(hi)) { return false }
    v^ = u16(x)
    return true
}

ui_combo_u8 :: proc(label: cstring, v: ^u8, names: []string) -> bool {
    cur := clamp(int(v^), 0, len(names) - 1)
    changed := false
    if im.BeginCombo(label, cs(names[cur])) {
        for name, i in names {
            if im.Selectable(cs(name), i == cur) && i != cur {
                v^ = u8(i)
                changed = true
            }
        }
        im.EndCombo()
    }
    return changed
}

ui_toggle_bit :: proc(label: cstring, flags: ^u8, bit: u8) -> bool {
    on := flags^ & bit != 0
    if !im.Checkbox(label, &on) { return false }
    if on { flags^ |= bit } else { flags^ &~= bit }
    return true
}

DevInspectorState :: struct {
    insp:      ecs.Inspector,
    authority: ecs.Sim,
    ready:     bool,
}

devui_inspector_init :: proc(st: ^DevInspectorState) {
    if st.ready { return }
    st.insp  = ecs.inspector_make()
    st.ready = true
}

devui_entity_list :: proc(st: ^DevInspectorState, w: ^ecs.World) {
    devui_inspector_init(st)
    ecs.inspector_validate(&st.insp, w)
    n := st.insp.filter_n
    im.SetNextItemWidth(-1)
    if ui_input_buf("##entfilter", st.insp.filter[:], &n, {}, "filter by id or component") {
        ecs.inspector_set_filter(&st.insp, string(st.insp.filter[:n]))
    }
    st.insp.filter_n = n
    if im.BeginChild("##entlist", { 0, 0 }, { .Borders }) {
        for id in ecs.inspector_entities(w, &st.insp) {
            label := fmt.ctprintf("#%d##ent", id)
            if im.Selectable(label, st.insp.selected == id) {
                ecs.inspector_select(&st.insp, w, id)
            }
        }
    }
    im.EndChild()
}

devui_entity_fields :: proc(st: ^DevInspectorState, w: ^ecs.World, sim: ^ecs.Sim) {
    devui_inspector_init(st)
    ecs.inspector_validate(&st.insp, w)
    editable := ecs.inspector_editable(sim)
    ui_hint("%s", ecs.inspector_authority_note(sim))
    if !ecs.world_is_valid(w, st.insp.selected) {
        ui_hint("No entity selected.")
        return
    }
    ui_text_col(DEVUI_GOLD, "Entity #%d", st.insp.selected)

    open: bool
    if !im.BeginTable("##fields", 2, im.TableFlags_RowBg | im.TableFlags_BordersInnerV | im.TableFlags_Resizable | im.TableFlags_SizingStretchProp) { return }
    im.TableSetupColumn("field", {}, 0.42)
    im.TableSetupColumn("value", {}, 0.58)
    for row, ri in ecs.inspector_rows(w, &st.insp) {
        im.PushIDInt(i32(ri))
        im.TableNextRow()
        im.TableNextColumn()
        if row.kind == .Component {
            open = !ecs.inspector_is_collapsed(&st.insp, row.comp)
            arrow := "v" if open else ">"
            if im.Selectable(fmt.ctprintf("%s %s", arrow, row.label), false, { .SpanAllColumns }) {
                ecs.inspector_toggle_collapsed(&st.insp, row.comp)
            }
            im.PopID()
            continue
        }
        im.Indent(f32(max(row.depth - 1, 0)) * 10)
        im.TextUnformatted(cs(row.label))
        im.Unindent(f32(max(row.depth - 1, 0)) * 10)
        im.TableNextColumn()
        im.SetNextItemWidth(-1)
        _devui_field_widget(row.field, editable && row.field.editable)
        im.PopID()
    }
    im.EndTable()
}

@(private = "file")
_devui_field_widget :: proc(f: ecs.FieldRef, editable: bool) {
    if !editable || f.kind == .Group || f.kind == .Unsupported {
        im.TextDisabled(cs(ecs.field_text(f)))
        return
    }
    #partial switch f.kind {
    case .Bool:
        v, _ := ecs.field_bool(f)
        if im.Checkbox("##v", &v) { ecs.field_set_bool(f, v) }
    case .Float:
        v, _ := ecs.field_f64(f)
        x := f32(v)
        lo, hi := f32(0), f32(0)
        if f.has_range { lo, hi = f32(f.range_min), f32(f.range_max) }
        if im.DragFloat("##v", &x, 0.1 if !f.has_range else (hi - lo) / 200, lo, hi, "%.3f") {
            ecs.field_set_f64(f, f64(x))
        }
    case .Int:
        v, _ := ecs.field_i64(f)
        x := i64(v)
        if im.DragScalar("##v", .S64, &x, 0.25) { ecs.field_set_i64(f, x) }
    case .Uint:
        v, _ := ecs.field_u64(f)
        x := u64(v)
        if im.DragScalar("##v", .U64, &x, 0.25) { ecs.field_set_u64(f, x) }
    case .Enum:
        names := ecs.enum_names(f.type)
        cur   := ecs.field_text(f)
        if im.BeginCombo("##v", cs(cur)) {
            for name in names {
                if im.Selectable(cs(name), name == cur) { ecs.field_set_text(f, name) }
            }
            im.EndCombo()
        }
    case:
        text := ecs.field_text(f)
        buf: [256]u8
        n := min(len(text), len(buf) - 1)
        copy(buf[:], text[:n])
        if ui_input_buf("##v", buf[:], &n, { .EnterReturnsTrue }) {
            ecs.field_set_text(f, string(buf[:n]))
        }
        ui_tooltip("Press Enter to apply")
    }
}
