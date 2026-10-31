package clockwork

Pose :: struct {
	pos:   [3]f32,
	yaw:   f32,
	pitch: f32,
	valid: bool,
}

PoseBuffer :: struct {
	prev: [MAX_PEERS]Pose,
	cur:  [MAX_PEERS]Pose,
}

pose_rotate :: proc(pb: ^PoseBuffer) {
	pb.prev = pb.cur
}

pose_set :: proc(pb: ^PoseBuffer, peer: PeerId, p: Pose) {
	if peer < 0 || int(peer) >= MAX_PEERS {return}
	pb.cur[peer] = p
}

pose_clear :: proc(pb: ^PoseBuffer, peer: PeerId) {
	if peer < 0 || int(peer) >= MAX_PEERS {return}
	pb.cur[peer] = {}
}

pose_blend :: proc(pb: ^PoseBuffer, peer: PeerId, alpha: f32) -> Pose {
	if peer < 0 || int(peer) >= MAX_PEERS {return {}}

	a := pb.prev[peer]
	b := pb.cur[peer]
	if !b.valid {return {}}
	if !a.valid {return b}

	t := clamp(alpha, 0, 1)
	return Pose {
		pos   = a.pos + (b.pos - a.pos) * t,
		yaw   = lerp_angle(a.yaw, b.yaw, t),
		pitch = a.pitch + (b.pitch - a.pitch) * t,
		valid = true,
	}
}
