package main

import cw "clockwork"

FOG_VISION_RADIUS :: f32(260)   
FOG_FADE_WIDTH    :: f32(160)   

is_fog_hidden :: proc(w: ^cw.World, id: int) -> bool {
    if !cw.world_has_component(w, id, .FogOfWar)          { return false }
    if !cw.world_is_valid(w, w.player_id)                  { return false }
    if !cw.world_has_component(w, id, .Transform)          { return false }
    if !cw.world_has_component(w, w.player_id, .Transform) { return false }

    ep  := cw.world_get_transform(w, id).position
    pp  := cw.world_get_transform(w, w.player_id).position
    dx  := ep[0] - pp[0]
    dy  := ep[1] - pp[1]
    lim := FOG_VISION_RADIUS + FOG_FADE_WIDTH
    return (dx*dx + dy*dy) >= lim*lim
}

init_fog     :: proc() {}
shutdown_fog :: proc() {}
