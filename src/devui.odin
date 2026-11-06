package main

import im   "../deps/imgui/imgui"
import imrl "../ui/imgui_raylib"

g_devui_demo: bool

@(private = "file") g_devui:       imrl.Backend
@(private = "file") g_devui_ready: bool
@(private = "file") g_devui_frame: bool

devui_init :: proc() {
    if g_devui_ready { return }
    ensure_user_dir(".")
    imrl.init(&g_devui, user_path("imgui.ini"), "data/fonts/body.ttf", 16)
    devui_apply_style()
    g_devui_ready = true
}

devui_shutdown :: proc() {
    if !g_devui_ready { return }
    imrl.shutdown(&g_devui)
    g_devui_ready = false
}

devui_begin_frame :: proc(dt: f32) {
    devui_init()
    imrl.new_frame(&g_devui, dt)
    g_devui_frame = true
}

devui_end_frame :: proc() {
    if !g_devui_frame { return }
    g_devui_frame = false
    imrl.render(&g_devui)
}

devui_wants_mouse    :: proc() -> bool { return g_devui_ready && imrl.wants_mouse() }
devui_wants_keyboard :: proc() -> bool { return g_devui_ready && imrl.wants_keyboard() }
devui_wants_text     :: proc() -> bool { return g_devui_ready && imrl.wants_text() }

devui_ignore_char :: proc(r: rune) {
    if g_devui_ready { imrl.ignore_char_this_frame(&g_devui, r) }
}

devui_texture :: imrl.texture_ref

devui_apply_style :: proc() {
    im.StyleColorsDark()
    st := im.GetStyle()
    st.WindowRounding    = 4
    st.FrameRounding     = 3
    st.GrabRounding      = 3
    st.TabRounding       = 3
    st.ScrollbarRounding = 3
    st.WindowBorderSize  = 1
    st.FramePadding      = { 6, 4 }
    st.ItemSpacing       = { 7, 5 }

    c := &st.Colors
    brass  := im.Vec4{ 0.75, 0.56, 0.23, 1 }
    brassh := im.Vec4{ 0.86, 0.66, 0.30, 1 }
    c[int(im.Col.WindowBg)]         = { 0.07, 0.06, 0.05, 0.96 }
    c[int(im.Col.ChildBg)]          = { 0.05, 0.04, 0.04, 0.60 }
    c[int(im.Col.PopupBg)]          = { 0.08, 0.07, 0.06, 0.98 }
    c[int(im.Col.Border)]           = { 0.30, 0.25, 0.18, 0.70 }
    c[int(im.Col.FrameBg)]          = { 0.14, 0.12, 0.09, 1 }
    c[int(im.Col.FrameBgHovered)]   = { 0.22, 0.18, 0.12, 1 }
    c[int(im.Col.FrameBgActive)]    = { 0.28, 0.22, 0.14, 1 }
    c[int(im.Col.TitleBg)]          = { 0.09, 0.08, 0.06, 1 }
    c[int(im.Col.TitleBgActive)]    = { 0.20, 0.15, 0.08, 1 }
    c[int(im.Col.MenuBarBg)]        = { 0.10, 0.08, 0.06, 1 }
    c[int(im.Col.CheckMark)]        = brassh
    c[int(im.Col.SliderGrab)]       = brass
    c[int(im.Col.SliderGrabActive)] = brassh
    c[int(im.Col.Button)]           = { 0.22, 0.17, 0.10, 1 }
    c[int(im.Col.ButtonHovered)]    = { 0.36, 0.27, 0.13, 1 }
    c[int(im.Col.ButtonActive)]     = { 0.48, 0.35, 0.15, 1 }
    c[int(im.Col.Header)]           = { 0.30, 0.23, 0.12, 0.80 }
    c[int(im.Col.HeaderHovered)]    = { 0.40, 0.30, 0.14, 0.90 }
    c[int(im.Col.HeaderActive)]     = { 0.50, 0.37, 0.16, 1 }
    c[int(im.Col.Tab)]              = { 0.16, 0.12, 0.08, 1 }
    c[int(im.Col.TabHovered)]       = { 0.40, 0.30, 0.14, 1 }
    c[int(im.Col.TabSelected)]      = { 0.30, 0.22, 0.11, 1 }
    c[int(im.Col.DockingPreview)]   = { 0.75, 0.56, 0.23, 0.60 }
    c[int(im.Col.SeparatorHovered)] = brass
    c[int(im.Col.ResizeGrip)]       = { 0.75, 0.56, 0.23, 0.25 }
    c[int(im.Col.ResizeGripHovered)] = brass
    c[int(im.Col.TextSelectedBg)]   = { 0.75, 0.56, 0.23, 0.35 }
    c[int(im.Col.NavCursor)]        = brassh
}
