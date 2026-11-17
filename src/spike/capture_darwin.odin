package spike

import "core:c"
import sg "sokol:gfx"

// Metal readback: the blit lives in native/capture_metal.m (built by ./build.sh spike).
when ODIN_ARCH == .arm64 {
    foreign import native { "native/capture_metal_arm64.a", "system:Metal.framework", "system:Foundation.framework" }
} else {
    foreign import native { "native/capture_metal_x64.a", "system:Metal.framework", "system:Foundation.framework" }
}

@(default_calling_convention = "c")
foreign native {
    tormentas_mtl_read_rgba8 :: proc(queue, texture: rawptr, width, height: c.int, out: [^]u8) -> c.int ---
}

// Reads an RGBA8 render target into `out` (w*h*4 bytes, top row first). Call after sg.commit().
read_target_rgba8 :: proc(img: sg.Image, w, h: i32, out: []u8) -> bool {
    info := sg.mtl_query_image_info(img)
    return tormentas_mtl_read_rgba8(sg.mtl_command_queue(), info.tex[info.active_slot], w, h, raw_data(out)) == 1
}
