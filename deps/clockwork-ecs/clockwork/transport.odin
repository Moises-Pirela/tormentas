package clockwork

Transport :: struct {
	user:        rawptr,
	send:        proc(user: rawptr, peer: PeerId, data: []u8, reliable: bool),
	broadcast:   proc(user: rawptr, data: []u8, reliable: bool),
	is_host:     proc(user: rawptr) -> bool,
	peer_active: proc(user: rawptr, peer: PeerId) -> bool,
	local_peer:  proc(user: rawptr) -> PeerId,
}

transport_send :: proc(t: ^Transport, peer: PeerId, data: []u8, reliable := true) {
	if t == nil || t.send == nil {return}
	t.send(t.user, peer, data, reliable)
}

transport_broadcast :: proc(t: ^Transport, data: []u8, reliable := true) {
	if t == nil {return}
	if t.broadcast != nil {
		t.broadcast(t.user, data, reliable)
		return
	}
	if t.send == nil || t.peer_active == nil {return}
	for peer in 0 ..< MAX_PEERS {
		if !t.peer_active(t.user, PeerId(peer)) {continue}
		t.send(t.user, PeerId(peer), data, reliable)
	}
}

transport_is_host :: proc(t: ^Transport) -> bool {
	if t == nil || t.is_host == nil {return true}
	return t.is_host(t.user)
}

transport_peer_active :: proc(t: ^Transport, peer: PeerId) -> bool {
	if t == nil || t.peer_active == nil {return false}
	return t.peer_active(t.user, peer)
}

transport_local_peer :: proc(t: ^Transport) -> PeerId {
	if t == nil || t.local_peer == nil {return INVALID_PEER}
	return t.local_peer(t.user)
}
