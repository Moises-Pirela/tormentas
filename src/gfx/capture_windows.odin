package gfx

import sg "sokol:gfx"

import d3d11 "vendor:directx/d3d11"

// D3D11 readback: copy the render target into a CPU-readable staging texture and map it.
// sokol_gfx has no readback API, but it exposes the device, the immediate context and the
// image's ID3D11Texture2D. Call after sg.commit(): sokol has issued the frame to the immediate
// context, so the copy is ordered after it.
_read_target_rgba8 :: proc(img: sg.Image, w, h: i32, out: []u8) -> bool {
    device := (^d3d11.IDevice)(sg.d3d11_device())
    ctx    := (^d3d11.IDeviceContext)(sg.d3d11_device_context())
    src    := (^d3d11.ITexture2D)(sg.d3d11_query_image_info(img).tex2d)
    if device == nil || ctx == nil || src == nil { return false }

    desc: d3d11.TEXTURE2D_DESC
    src->GetDesc(&desc)
    if desc.Format != .R8G8B8A8_UNORM || i32(desc.Width) != w || i32(desc.Height) != h { return false }
    desc.MipLevels      = 1
    desc.ArraySize      = 1
    desc.SampleDesc     = { Count = 1, Quality = 0 }
    desc.Usage          = .STAGING
    desc.BindFlags      = {}
    desc.CPUAccessFlags = { .READ }
    desc.MiscFlags      = {}

    staging: ^d3d11.ITexture2D
    if device->CreateTexture2D(&desc, nil, &staging) < 0 || staging == nil { return false }
    defer staging->Release()

    ctx->CopyResource(staging, src)
    mapped: d3d11.MAPPED_SUBRESOURCE
    if ctx->Map(staging, 0, .READ, {}, &mapped) < 0 { return false }
    defer ctx->Unmap(staging, 0)

    row := int(w) * 4
    for y in 0 ..< int(h) {
        src_row := ([^]u8)(mapped.pData)[y * int(mapped.RowPitch):][:row]
        copy(out[y * row:][:row], src_row)
    }
    return true
}
