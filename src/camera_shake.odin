package main

import rl   "vendor:raylib"
import      "core:math"

SHAKE_TRAUMA_DECAY :: f32(4.0) 
SHAKE_MAX_OFFSET   :: f32(8.0) 

g_cam_trauma: f32

camera_shake :: proc(trauma: f32) {
    g_cam_trauma = clamp(g_cam_trauma + trauma, 0, 1)
}

tick_camera_shake :: proc(dt: f32) {
    if g_cam_trauma <= 0 { return }

    shake := g_cam_trauma * g_cam_trauma  

    t := f32(rl.GetTime())
    noise_x := math.sin(t * 71.3) * math.cos(t * 33.7)
    noise_y := math.sin(t * 53.1) * math.cos(t * 47.9)

    g_camera.offset.x += noise_x * shake * SHAKE_MAX_OFFSET
    g_camera.offset.y += noise_y * shake * SHAKE_MAX_OFFSET

    g_cam_trauma = max(g_cam_trauma - SHAKE_TRAUMA_DECAY * dt, 0)
}
