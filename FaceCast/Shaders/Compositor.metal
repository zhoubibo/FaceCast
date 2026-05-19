#include <metal_stdlib>
using namespace metal;

// Placeholder picture-in-picture compositing kernel.
//
// Currently copies the screen texture straight to the output. The real kernel
// will scale and blend the camera texture as an overlay according to the PiP
// layout (position, size, shape) passed in via a uniforms buffer.
kernel void composite(texture2d<float, access::read>  screenTexture [[texture(0)]],
                       texture2d<float, access::read>  cameraTexture [[texture(1)]],
                       texture2d<float, access::write> outputTexture [[texture(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    // TODO: sample cameraTexture and blend it as a PiP overlay.
    outputTexture.write(screenTexture.read(gid), gid);
}
