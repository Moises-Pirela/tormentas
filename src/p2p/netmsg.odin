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

PLAYER_ABILITY_SLOT_COUNT :: 4

PlayerAbilityState :: struct {
    energy_frac:   u8,
    cooldown_frac: [PLAYER_ABILITY_SLOT_COUNT]u8,
}

PLAYER_ABILITY_STATE_SIZE :: size_of(PlayerAbilityState)

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
session_broadcast_snapshot :: proc(s: ^Session, ack_by_slot: [MAX_PLAYERS]u32, entities: []SyncEntity, abilities: [MAX_PLAYERS]PlayerAbilityState) {
    n := min(len(entities), MAX_SNAPSHOT_ENTITIES)
    size := 1 + 4 + 4 + n * SYNC_ENTITY_SIZE + MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE
    pkt := make([]u8, size, context.temp_allocator)
    pkt[0] = u8(MsgType.HostSnapshot)

    ecount := u32(n)
    mem.copy(&pkt[5], &ecount, 4)

    cur := 9
    for i in 0..<n {
        encode_sync_entity(entities[i], pkt[cur:cur+SYNC_ENTITY_SIZE])
        cur += SYNC_ENTITY_SIZE
    }

    abilities := abilities
    mem.copy(&pkt[cur], &abilities, MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE)
    cur += MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE

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

    if ecount > MAX_SNAPSHOT_ENTITIES { return }
    n := int(ecount)
    expected := 8 + n * SYNC_ENTITY_SIZE + MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE
    if len(data) < expected { return }
    clear(&s.snapshot_entities)
    for _ in 0..<n {
        if cur + SYNC_ENTITY_SIZE > len(data) { break }
        e, ok := decode_sync_entity(data[cur:cur+SYNC_ENTITY_SIZE])
        if !ok { break }
        append(&s.snapshot_entities, e)
        cur += SYNC_ENTITY_SIZE
    }

    if cur + MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE <= len(data) {
        mem.copy(&s.snapshot_abilities, &data[cur], MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE)
        cur += MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE
    }

    s.snapshot_ack  = ack
    s.has_snapshot  = true
}

RaidOutcome :: enum u8 { Extracted, Died }

RaidResultMsg :: struct {
    outcome:        RaidOutcome,
    _pad:           [3]u8,
    gold:           i32,
    serums:         i32,
    extract_value:  i32,
    enemies_killed: u16,
    elites_killed:  u16,
    bosses_killed:  u16,
    _pad2:          [2]u8,
}

RAID_RESULT_MSG_SIZE :: size_of(RaidResultMsg)

session_peer_for_slot :: proc(s: ^Session, slot: int) -> ^Peer {
    for &p in s.peers {
        if p.active && p.slot == slot { return &p }
    }
    return nil
}

session_send_raid_result_to_peer :: proc(p: ^Peer, outcome: RaidOutcome, gold, serums, extract_value: i32,
                                          enemies_killed, elites_killed, bosses_killed: u16) {
    msg := RaidResultMsg{
        outcome = outcome, gold = gold, serums = serums, extract_value = extract_value,
        enemies_killed = enemies_killed, elites_killed = elites_killed, bosses_killed = bosses_killed,
    }
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
    s.raid_result_outcome        = msg.outcome
    s.raid_result_gold           = msg.gold
    s.raid_result_serums         = msg.serums
    s.raid_result_extract_value  = msg.extract_value
    s.raid_result_enemies_killed = msg.enemies_killed
    s.raid_result_elites_killed  = msg.elites_killed
    s.raid_result_bosses_killed  = msg.bosses_killed
    s.has_raid_result            = true
}

ENTITY_SYNC_STR_LEN :: 32
ENTITY_SYNC_DESTROY  :: u8(255)

EntitySyncMsg :: struct {
    wire_id:   u32,
    component: u8,
    path_len:  u8,
    value_len: u8,
    _pad:      u8,
    path:      [ENTITY_SYNC_STR_LEN]u8,
    value:     [ENTITY_SYNC_STR_LEN]u8,
}

ENTITY_SYNC_MSG_SIZE :: size_of(EntitySyncMsg)

session_broadcast_entity_sync :: proc(s: ^Session, wire_id: u32, component: u8, path, value: string) {
    msg: EntitySyncMsg
    msg.wire_id   = wire_id
    msg.component = component
    msg.path_len  = u8(min(len(path), ENTITY_SYNC_STR_LEN))
    msg.value_len = u8(min(len(value), ENTITY_SYNC_STR_LEN))
    copy(msg.path[:], path[:msg.path_len])
    copy(msg.value[:], value[:msg.value_len])

    pkt: [1 + ENTITY_SYNC_MSG_SIZE]u8
    pkt[0] = u8(MsgType.EntitySync)
    mem.copy(&pkt[1], &msg, ENTITY_SYNC_MSG_SIZE)
    _broadcast(s, pkt[:])
}

session_broadcast_entity_destroy :: proc(s: ^Session, wire_id: u32) {
    session_broadcast_entity_sync(s, wire_id, ENTITY_SYNC_DESTROY, "", "")
}

@(private)
_handle_entity_sync :: proc(s: ^Session, data: []u8) {
    if len(data) < ENTITY_SYNC_MSG_SIZE { return }
    msg: EntitySyncMsg
    mem.copy(&msg, raw_data(data), ENTITY_SYNC_MSG_SIZE)
    append(&s.entity_syncs, msg)
}

session_drain_entity_syncs :: proc(s: ^Session) -> []EntitySyncMsg {
    if len(s.entity_syncs) == 0 { return nil }
    out := make([]EntitySyncMsg, len(s.entity_syncs), context.temp_allocator)
    copy(out, s.entity_syncs[:])
    clear(&s.entity_syncs)
    return out
}
