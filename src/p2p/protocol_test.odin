package p2p

import "core:testing"
import "core:mem"

@(test)
input_frame_round_trip :: proc(t: ^testing.T) {
    original := InputFrame{tick = 0xffff_fffe, peer = 3, actions = {.Fire, .Dodge, .Interact}, move = {-0.5, 1}, aim = {200, -300}}
    bytes: [INPUT_FRAME_SIZE + 2]u8
    bytes[0], bytes[len(bytes)-1] = 0xab, 0xcd
    encode_frame(original, bytes[1:len(bytes)-1])
    decoded, ok := decode_frame(bytes[1:len(bytes)-1])
    testing.expect(t, ok && decoded == original)
    testing.expect(t, bytes[0] == 0xab && bytes[len(bytes)-1] == 0xcd)
}

@(test)
input_frame_rejects_every_truncated_length :: proc(t: ^testing.T) {
    bytes: [INPUT_FRAME_SIZE]u8
    for n in 0..<INPUT_FRAME_SIZE {
        _, ok := decode_frame(bytes[:n])
        testing.expect(t, !ok)
    }
}

@(test)
sync_entity_round_trip_and_truncation :: proc(t: ^testing.T) {
    original := SyncEntity{wire_id = 0xffff_ffff, kind = .Projectile, slot = 3, pos = {-2, 0, 50}, rot = 1.25, vel = {10, -20, 0}, hp_frac = 128, archetype = 255}
    bytes: [SYNC_ENTITY_SIZE]u8
    encode_sync_entity(original, bytes[:])
    decoded, ok := decode_sync_entity(bytes[:])
    testing.expect(t, ok && decoded == original)
    for n in 0..<SYNC_ENTITY_SIZE {
        _, valid := decode_sync_entity(bytes[:n])
        testing.expect(t, !valid)
    }
}

@(test)
editor_messages_reject_truncation_and_drain_once :: proc(t: ^testing.T) {
    s := new(Session)
    defer free(s)
    defer delete(s.editor_ops)
    op := EditorOp{action = .Paint, brush = 5, tx = -12, ty = 300, target_level = 2}
    bytes: [EDITOR_OP_SIZE]u8
    mem.copy(&bytes[0], &op, EDITOR_OP_SIZE)
    for n in 0..<EDITOR_OP_SIZE { _handle_editor_op(s, bytes[:n]) }
    testing.expect(t, len(s.editor_ops) == 0)
    _handle_editor_op(s, bytes[:])
    _handle_level_load_msg(s, []u8{0x34, 0x12})
    ops, level := session_drain_editor(s)
    testing.expect(t, len(ops) == 1 && ops[0] == op && level == 0x1234)
    again, next_level := session_drain_editor(s)
    testing.expect(t, len(again) == 0 && next_level == 0)
}

@(test)
raid_result_rejects_truncation :: proc(t: ^testing.T) {
    s := new(Session)
    defer free(s)
    original := RaidResultMsg{outcome = .Extracted, gold = 500, serums = 2, extract_value = 900, enemies_killed = 40, elites_killed = 3, bosses_killed = 1}
    bytes: [RAID_RESULT_MSG_SIZE]u8
    mem.copy(&bytes[0], &original, RAID_RESULT_MSG_SIZE)
    for n in 0..<RAID_RESULT_MSG_SIZE { _handle_raid_result(s, bytes[:n]) }
    testing.expect(t, !s.has_raid_result)
    _handle_raid_result(s, bytes[:])
    testing.expect(t, s.has_raid_result && s.raid_result_outcome == .Extracted)
    testing.expect(t, s.raid_result_gold == 500 && s.raid_result_serums == 2 && s.raid_result_extract_value == 900)
    testing.expect(t, s.raid_result_enemies_killed == 40 && s.raid_result_elites_killed == 3 && s.raid_result_bosses_killed == 1)
}

@(test)
offline_transport_cannot_claim_connection :: proc(t: ^testing.T) {
    when !STEAM_ENABLED {
        s := new(Session)
        defer free(s)
        testing.expect(t, !session_host(s) && !session_join(s, 123))
        testing.expect(t, !session_host_loopback(s, 7777) && !session_join_loopback(s, 7777))
        testing.expect(t, s.state == .Offline && !session_is_online(s))
    }
}

@(test)
snapshot_rejects_incomplete_packets_without_losing_previous_state :: proc(t: ^testing.T) {
    s := new(Session)
    defer free(s)
    defer delete(s.snapshot_entities)
    original := SyncEntity{wire_id = 42, kind = .Player, slot = 1, hp_frac = 200}
    abilities: [MAX_PLAYERS]PlayerAbilityState
    abilities[1] = {energy_frac = 123, cooldown_frac = {0, 50, 100, 255}}
    packet: [8 + SYNC_ENTITY_SIZE + MAX_PLAYERS * PLAYER_ABILITY_STATE_SIZE]u8
    ack, count := u32(17), u32(1)
    mem.copy(&packet[0], &ack, 4)
    mem.copy(&packet[4], &count, 4)
    encode_sync_entity(original, packet[8:])
    mem.copy(&packet[8 + SYNC_ENTITY_SIZE], &abilities, size_of(abilities))
    _handle_host_snapshot(s, packet[:])
    testing.expect(t, s.has_snapshot && s.snapshot_ack == 17 && len(s.snapshot_entities) == 1)
    testing.expect(t, s.snapshot_entities[0] == original && s.snapshot_abilities == abilities)
    s.has_snapshot = false
    for n in 0..<len(packet) {
        _handle_host_snapshot(s, packet[:n])
        testing.expect(t, !s.has_snapshot && s.snapshot_ack == 17 && len(s.snapshot_entities) == 1)
        if len(s.snapshot_entities) == 1 {
            testing.expect(t, s.snapshot_entities[0] == original && s.snapshot_abilities == abilities)
        }
    }
    count = MAX_SNAPSHOT_ENTITIES + 1
    mem.copy(&packet[4], &count, 4)
    _handle_host_snapshot(s, packet[:])
    testing.expect(t, !s.has_snapshot)
}
