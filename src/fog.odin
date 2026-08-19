package main


FOG_VISION_RADIUS :: f32(260)
FOG_FADE_WIDTH    :: f32(160)

is_fog_hidden :: proc(w: ^World, id: int) -> bool {
    if !world_has_component(w, id, .FogOfWar)          { return false }
    if !world_is_valid(w, w.player_id)                  { return false }
    if !world_has_component(w, id, .Transform)          { return false }
    if !world_has_component(w, w.player_id, .Transform) { return false }

    ep  := comp_get(w, id, .Transform, TransformComp).position
    pp  := comp_get(w, w.player_id, .Transform, TransformComp).position
    dx  := ep[0] - pp[0]
    dy  := ep[1] - pp[1]
    lim := FOG_VISION_RADIUS + FOG_FADE_WIDTH
    return (dx*dx + dy*dy) >= lim*lim
}

init_fog     :: proc() {}
shutdown_fog :: proc() {}
