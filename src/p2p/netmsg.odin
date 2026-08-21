package p2p

import "core:mem"

SyncKind :: enum u8 {
    Player,
    Enemy,
    Projectile,
}

SyncEntity :: struct {
    wire_id: u32,
    kind:    SyncKind,
    slot:    u8,
    _pad:    u16,
    pos:     [3]f32,
    rot:     f32,
    vel:     [3]f32,
    hp_frac:   u8,
    archetype: u8,
    _pad2:     u16,
}

SYNC_ENTITY_SIZE :: size_of(SyncEntity)

MAX_SNAPSHOT_ENTITIES :: 256

encode_sync_entity :: proc(e: SyncEntity, dst: []u8) {
    assert(len(dst) >= SYNC_ENTITY_SIZE)
    e := e
    mem.copy(raw_data(dst), &e, SYNC_ENTITY_SIZE)
}

decode_sync_entity :: proc(src: []u8) -> (e: SyncEntity, ok: bool) {
    if len(src) < SYNC_ENTITY_SIZE { return {}, false }
    mem.copy(&e, raw_data(src), SYNC_ENTITY_SIZE)
    return e, true
}

session_send_client_input :: proc(s: ^Session, frame: InputFrame) {
    if s.state != .Connected { return }
    pkt: [1 + INPUT_FRAME_SIZE]u8
    pkt[0] = u8(MsgType.ClientInput)
    encode_frame(frame, pkt[1:])
    _send(s, pkt[:], false)
}

// Encodes once and sends the same entity payload to every connected peer, each with its own
// ack_seq — reconciliation for the receiving player's own slot is derived client-side from the
// matching Player-kind entry already in `entities`, so no separate per-recipient reconcile blob
// is needed here.
session_broadcast_snapshot :: proc(s: ^Session, ack_by_slot: [MAX_PLAYERS]u32, entities: []SyncEntity) {
    n := min(len(entities), MAX_SNAPSHOT_ENTITIES)
    size := 1 + 4 + 4 + n * SYNC_ENTITY_SIZE
    pkt := make([]u8, size, context.temp_allocator)
    pkt[0] = u8(MsgType.HostSnapshot)

    ecount := u32(n)
    mem.copy(&pkt[5], &ecount, 4)

    cur := 9
    for i in 0..<n {
        encode_sync_entity(entities[i], pkt[cur:cur+SYNC_ENTITY_SIZE])
        cur += SYNC_ENTITY_SIZE
    }

    for &p in s.peers {
        if !p.active || !p.connected { continue }
        ack := ack_by_slot[p.slot]
        mem.copy(&pkt[1], &ack, 4)
        _send_to_peer(&p, pkt, false)
    }
}

@(private)
_handle_host_snapshot :: proc(s: ^Session, data: []u8) {
    if len(data) < 4 + 4 { return }
    cur := 0
    ack: u32
    mem.copy(&ack, &data[cur], 4); cur += 4

    ecount: u32
    mem.copy(&ecount, &data[cur], 4); cur += 4

    n := min(int(ecount), MAX_SNAPSHOT_ENTITIES)
    clear(&s.snapshot_entities)
    for _ in 0..<n {
        if cur + SYNC_ENTITY_SIZE > len(data) { break }
        e, ok := decode_sync_entity(data[cur:cur+SYNC_ENTITY_SIZE])
        if !ok { break }
        append(&s.snapshot_entities, e)
        cur += SYNC_ENTITY_SIZE
    }

    s.snapshot_ack  = ack
    s.has_snapshot  = true
}

RaidOutcome :: enum u8 { Extracted, Died }

RaidResultMsg :: struct {
    outcome:       RaidOutcome,
    _pad:          [3]u8,
    gold:          i32,
    serums:        i32,
    extract_value: i32,
}

RAID_RESULT_MSG_SIZE :: size_of(RaidResultMsg)

session_peer_for_slot :: proc(s: ^Session, slot: int) -> ^Peer {
    for &p in s.peers {
        if p.active && p.slot == slot { return &p }
    }
    return nil
}

session_send_raid_result_to_peer :: proc(p: ^Peer, outcome: RaidOutcome, gold, serums, extract_value: i32) {
    msg := RaidResultMsg{ outcome = outcome, gold = gold, serums = serums, extract_value = extract_value }
    pkt: [1 + RAID_RESULT_MSG_SIZE]u8
    pkt[0] = u8(MsgType.RaidResult)
    mem.copy(&pkt[1], &msg, RAID_RESULT_MSG_SIZE)
    _send_to_peer(p, pkt[:])
}

@(private)
_handle_raid_result :: proc(s: ^Session, data: []u8) {
    if len(data) < RAID_RESULT_MSG_SIZE { return }
    msg: RaidResultMsg
    mem.copy(&msg, raw_data(data), RAID_RESULT_MSG_SIZE)
    s.raid_result_outcome       = msg.outcome
    s.raid_result_gold          = msg.gold
    s.raid_result_serums        = msg.serums
    s.raid_result_extract_value = msg.extract_value
    s.has_raid_result           = true
}
