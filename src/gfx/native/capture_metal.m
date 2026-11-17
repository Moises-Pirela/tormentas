// GPU -> CPU readback of a sokol render-target image on the Metal backend.
//
// sokol_gfx has no readback API (sg_copy_* only goes CPU->GPU or GPU->GPU), but it exposes the
// native MTLCommandQueue and the image's MTLTexture. Call this *after* sg_commit(): sokol has
// committed the frame's command buffer to the same queue, so ours runs after it. The blit works
// whatever the texture's storage mode (sokol's render targets are private).
//
// Built into native/capture_metal_<arch>.a by `./build.sh spike`.
#import <Metal/Metal.h>
#include <string.h>

int tormentas_mtl_read_rgba8(void* queue_ptr, void* texture_ptr, int width, int height, unsigned char* out) {
    if (!queue_ptr || !texture_ptr || !out || width <= 0 || height <= 0) return 0;
    id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)queue_ptr;
    id<MTLTexture>      tex   = (__bridge id<MTLTexture>)texture_ptr;
    if (tex.pixelFormat != MTLPixelFormatRGBA8Unorm) return 0;

    NSUInteger bytes_per_row = (NSUInteger)width * 4;
    NSUInteger size          = bytes_per_row * (NSUInteger)height;
    id<MTLBuffer> buf = [queue.device newBufferWithLength:size options:MTLResourceStorageModeShared];
    if (!buf) return 0;

    id<MTLCommandBuffer>      cmd  = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
    [blit copyFromTexture:tex
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
                 toBuffer:buf
        destinationOffset:0
   destinationBytesPerRow:bytes_per_row
 destinationBytesPerImage:size];
    [blit endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    if (cmd.status != MTLCommandBufferStatusCompleted) return 0;

    memcpy(out, buf.contents, size);
    return 1;
}
