package p2p

import sw  "../../steamworks"
import "core:fmt"

DISCONNECT_TIMEOUT  :: f32(6.0)
MAX_DISCONNECT_STEP :: f32(0.5)
MAX_SAVE_BYTES       :: 65536

MAX_PLAYERS      :: 4
MAX_REMOTE_PEERS :: MAX_PLAYERS - 1

MsgType :: enum u8 {
    Hello           = 1,
    HelloAck        = 2,
    Ready           = 3,
    SlotAssign      = 4,
    EditorOp        = 5,
    LevelLoad       = 6,
    EditorModOp     = 7,
    CharacterData   = 8,
    ClientInput     = 9,
    HostSnapshot    = 10,
    RaidResult      = 11,
    RosterName      = 12,
    RosterCharData  = 13,
    RosterLeft      = 14,
}

SessionState :: enum {
    Offline,
    Hosting,
    Connecting,
    Connected,
    Disconnected,
}

NAME_SIZE :: 25

RosterEntry :: struct {
    known:      bool,
    name:       [NAME_SIZE]u8,
    char_data:  [MAX_SAVE_BYTES]u8,
    char_len:   int,
    char_ready: bool,
}

Peer :: struct {
    conn:       sw.HSteamNetConnection,
    active:     bool,
    slot:       int,
    connected:  bool,
    peer_ready: bool,

    no_recv_timer:  f32,
    char_data_sent: bool,

    latest_client_input: InputFrame,
    has_client_input:    bool,
}

Session :: struct {
    state:       SessionState,
    conn:        sw.HSteamNetConnection,
    listen_sock: sw.HSteamListenSocket,
    local_slot:  int,
    peer_ready:  bool,

    local_name:  [NAME_SIZE]u8,

    peers: [MAX_REMOTE_PEERS]Peer,

    roster: [MAX_PLAYERS]RosterEntry,

    editor_ops:         [dynamic]EditorOp,
    editor_mod_ops:     [dynamic]EditorModOp,
    pending_level_load: int,

    no_recv_timer: f32,

    char_data_sent: bool,

    snapshot_entities:   [dynamic]SyncEntity,
    snapshot_ack:        u32,
    has_snapshot:        bool,

    raid_result_outcome:       RaidOutcome,
    raid_result_gold:          i32,
    raid_result_serums:        i32,
    raid_result_extract_value: i32,
    has_raid_result:           bool,
}

is_host :: proc(s: ^Session) -> bool {
    return s.listen_sock != 0
}

session_host :: proc(s: ^Session) -> bool {
    socks  := sw.NetworkingSockets_SteamAPI()
    listen := sw.NetworkingSockets_CreateListenSocketP2P(socks, 0, 0, nil)
    if listen == 0 {
        fmt.eprintln("[p2p] CreateListenSocketP2P failed")
        return false
    }
    s.listen_sock = listen
    s.local_slot  = 0
    s.state       = .Hosting
    fmt.println("[p2p] hosting via Steam P2P — waiting for peers")
    return true
}

session_join :: proc(s: ^Session, host_steam_id: sw.CSteamID) -> bool {
    if host_steam_id == 0 { return false }
    identity: sw.SteamNetworkingIdentity
    sw.NetworkingIdentity_SetSteamID(&identity, host_steam_id)
    socks := sw.NetworkingSockets_SteamAPI()
    conn  := sw.NetworkingSockets_ConnectP2P(socks, &identity, 0, 0, nil)
    if conn == sw.HSteamNetConnection_Invalid {
        fmt.eprintln("[p2p] ConnectP2P failed")
        return false
    }
    s.conn       = conn
    s.local_slot = -1
    s.state      = .Connecting
    fmt.printf("[p2p] connecting to %d via Steam P2P\n", u64(host_steam_id))
    return true
}

session_host_loopback :: proc(s: ^Session, port: u16) -> bool {
    _allow_unauthenticated_ip()
    socks  := sw.NetworkingSockets_SteamAPI()
    addr   := _loopback_addr(port)
    listen := sw.NetworkingSockets_CreateListenSocketIP(socks, &addr, 0, nil)
    if listen == 0 {
        fmt.eprintln("[p2p] CreateListenSocketIP failed")
        return false
    }
    s.listen_sock = listen
    s.local_slot  = 0
    s.state       = .Hosting
    fmt.printf("[p2p] hosting on 127.0.0.1:%d (loopback)\n", port)
    return true
}

session_join_loopback :: proc(s: ^Session, port: u16) -> bool {
    _allow_unauthenticated_ip()
    socks := sw.NetworkingSockets_SteamAPI()
    addr  := _loopback_addr(port)
    conn  := sw.NetworkingSockets_ConnectByIPAddress(socks, &addr, 0, nil)
    if conn == sw.HSteamNetConnection_Invalid {
        fmt.eprintln("[p2p] ConnectByIPAddress failed")
        return false
    }
    s.conn       = conn
    s.local_slot = -1
    s.state      = .Connecting
    fmt.printf("[p2p] connecting to 127.0.0.1:%d (loopback)\n", port)
    return true
}

@(private)
_allow_unauthenticated_ip :: proc() {
    utils := sw.NetworkingUtils_SteamAPI()
    allow: i32 = 1
    sw.NetworkingUtils_SetConfigValue(utils, .IP_AllowWithoutAuth, .Global, 0, .Int32, &allow)
}

@(private)
_loopback_addr :: proc(port: u16) -> sw.SteamNetworkingIPAddr {
    addr := sw.SteamNetworkingIPAddr{ port = port }
    addr.ipv6[10] = 0xFF
    addr.ipv6[11] = 0xFF
    addr.ipv6[12] = 127
    addr.ipv6[15] = 1
    return addr
}

session_shutdown :: proc(s: ^Session) {
    if s.state == .Offline { return }
    socks := sw.NetworkingSockets_SteamAPI()
    if s.conn != sw.HSteamNetConnection_Invalid {
        sw.NetworkingSockets_CloseConnection(socks, s.conn, 0, nil, false)
    }
    for &p in s.peers {
        if p.active && p.conn != sw.HSteamNetConnection_Invalid {
            sw.NetworkingSockets_CloseConnection(socks, p.conn, 0, nil, false)
        }
    }
    if s.listen_sock != 0 {
        sw.NetworkingSockets_CloseListenSocket(socks, s.listen_sock)
    }
    delete(s.editor_ops)
    delete(s.editor_mod_ops)
    delete(s.snapshot_entities)
    s^ = {}
}

session_poll :: proc(s: ^Session, dt: f32) {
    if s.state == .Offline { return }
    socks := sw.NetworkingSockets_SteamAPI()

    if is_host(s) {
        for &p in s.peers {
            if !p.active { continue }
            _poll_peer(s, &p, socks)
        }
        return
    }

    if s.conn == sw.HSteamNetConnection_Invalid { return }

    msgs: [16]^sw.SteamNetworkingMessage
    for {
        n := sw.NetworkingSockets_ReceiveMessagesOnConnection(socks, s.conn, &msgs[0], 16)
        if n <= 0 { break }
        for i in 0..<n {
            msg  := msgs[i]
            data := (cast([^]u8)msg.pData)[:msg.cbSize]
            _handle_client(s, data)
            msg.pfnRelease(msg)
        }
    }

    if s.state == .Connected {
        s.no_recv_timer += min(dt, MAX_DISCONNECT_STEP)
        if s.no_recv_timer >= DISCONNECT_TIMEOUT {
            fmt.println("[p2p] peer timed out — marking disconnected")
            s.state = .Disconnected
        }
    }
}

@(private)
_poll_peer :: proc(s: ^Session, p: ^Peer, socks: ^sw.INetworkingSockets) {
    msgs: [16]^sw.SteamNetworkingMessage
    for {
        n := sw.NetworkingSockets_ReceiveMessagesOnConnection(socks, p.conn, &msgs[0], 16)
        if n <= 0 { break }
        for i in 0..<n {
            msg  := msgs[i]
            data := (cast([^]u8)msg.pData)[:msg.cbSize]
            _handle_host(s, p, data)
            msg.pfnRelease(msg)
        }
    }

    if p.connected {
        p.no_recv_timer += min(1.0/60.0, MAX_DISCONNECT_STEP)
    }
}

@(private)
_free_peer_slot :: proc(s: ^Session) -> ^Peer {
    for &p in s.peers {
        if !p.active { return &p }
    }
    return nil
}

@(private)
_next_free_player_slot :: proc(s: ^Session) -> int {
    taken: [MAX_PLAYERS]bool
    taken[0] = true
    for &p in s.peers {
        if p.active { taken[p.slot] = true }
    }
    for slot in 1..<MAX_PLAYERS {
        if !taken[slot] { return slot }
    }
    return -1
}

session_on_conn_changed :: proc(s: ^Session, ev: ^sw.SteamNetConnectionStatusChangedCallback) {
    socks := sw.NetworkingSockets_SteamAPI()

    if is_host(s) {
        switch ev.info.eState {
        case .Connecting:
            if ev.eOldState == .None && ev.info.hListenSocket == s.listen_sock {
                slot := _next_free_player_slot(s)
                p    := _free_peer_slot(s)
                if slot < 0 || p == nil {
                    fmt.eprintln("[p2p] session full — rejecting connection")
                    sw.NetworkingSockets_CloseConnection(socks, ev.hConn, 0, nil, false)
                } else if sw.NetworkingSockets_AcceptConnection(socks, ev.hConn) == .OK {
                    p^ = {}
                    p.conn   = ev.hConn
                    p.active = true
                    p.slot   = slot
                    fmt.printf("[p2p] accepted incoming connection into slot %d\n", slot)
                } else {
                    sw.NetworkingSockets_CloseConnection(socks, ev.hConn, 0, nil, false)
                }
            }
        case .Connected:
            if p := _peer_for_conn(s, ev.hConn); p != nil && !p.connected {
                p.connected = true
                _send_slot_assign(s, p)
                _send_hello_to(s, p)
                _send_known_roster_to(s, p)
                fmt.printf("[p2p] peer connected in slot %d\n", p.slot)
            }
        case .ClosedByPeer, .ProblemDetectedLocally:
            if p := _peer_for_conn(s, ev.hConn); p != nil {
                fmt.printf("[p2p] slot %d disconnected: %v\n", p.slot, ev.info.eState)
                slot := p.slot
                s.roster[slot] = {}
                p^ = {}
                _broadcast_roster_left(s, slot)
            }
        case .None, .FindingRoute, .FinWait, .Linger, .Dead, ._Force32Bit:
        }
        return
    }

    switch ev.info.eState {
    case .Connected:
        if ev.hConn == s.conn && s.state == .Connecting {
            s.state = .Connected
            _send_hello(s)
            fmt.println("[p2p] connection established")
        }
    case .ClosedByPeer, .ProblemDetectedLocally:
        if ev.hConn == s.conn && s.state != .Offline {
            fmt.printf("[p2p] connection closed: %v\n", ev.info.eState)
            s.state = .Disconnected
        }
    case .None, .Connecting, .FindingRoute, .FinWait, .Linger, .Dead, ._Force32Bit:
    }
}

@(private)
_peer_for_conn :: proc(s: ^Session, conn: sw.HSteamNetConnection) -> ^Peer {
    for &p in s.peers {
        if p.active && p.conn == conn { return &p }
    }
    return nil
}

session_send_char_data :: proc(s: ^Session, data: []u8) {
    if len(data) == 0 { return }
    pkt := make([]u8, 1 + len(data), context.temp_allocator)
    pkt[0] = u8(MsgType.CharacterData)
    copy(pkt[1:], data)
    if is_host(s) {
        _broadcast(s, pkt)
    } else {
        if s.state != .Connected { return }
        _send(s, pkt)
    }
}

session_send_char_data_to_peer :: proc(p: ^Peer, data: []u8) {
    if len(data) == 0 { return }
    pkt := make([]u8, 1 + len(data), context.temp_allocator)
    pkt[0] = u8(MsgType.CharacterData)
    copy(pkt[1:], data)
    _send_to_peer(p, pkt)
}

session_is_online :: proc(s: ^Session) -> bool {
    if is_host(s) {
        for &p in s.peers {
            if p.active && p.connected { return true }
        }
        return false
    }
    return s.state == .Connected && s.local_slot >= 0
}

session_is_disconnected :: proc(s: ^Session) -> bool { return s.state == .Disconnected }

session_active_peer_count :: proc(s: ^Session) -> int {
    n := 0
    for &p in s.peers {
        if p.active && p.connected { n += 1 }
    }
    return n
}

@(private)
_send :: proc(s: ^Session, data: []u8, reliable: bool = true) {
    if s.conn == sw.HSteamNetConnection_Invalid { return }
    socks := sw.NetworkingSockets_SteamAPI()
    flags := sw.nSteamNetworkingSend_Reliable if reliable else
             (sw.nSteamNetworkingSend_Unreliable | sw.nSteamNetworkingSend_NoNagle)
    sw.NetworkingSockets_SendMessageToConnection(socks, s.conn,
        raw_data(data), u32(len(data)), flags, nil)
}

@(private)
_send_to_peer :: proc(p: ^Peer, data: []u8, reliable: bool = true) {
    if !p.active || p.conn == sw.HSteamNetConnection_Invalid { return }
    socks := sw.NetworkingSockets_SteamAPI()
    flags := sw.nSteamNetworkingSend_Reliable if reliable else
             (sw.nSteamNetworkingSend_Unreliable | sw.nSteamNetworkingSend_NoNagle)
    sw.NetworkingSockets_SendMessageToConnection(socks, p.conn,
        raw_data(data), u32(len(data)), flags, nil)
}

@(private)
_broadcast :: proc(s: ^Session, data: []u8, reliable: bool = true, except: ^Peer = nil) {
    for &p in s.peers {
        if !p.active || !p.connected { continue }
        if except != nil && &p == except { continue }
        _send_to_peer(&p, data, reliable)
    }
}

@(private)
_send_hello :: proc(s: ^Session) {
    pkt: [1 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.Hello)
    copy(pkt[1:], s.local_name[:])
    _send(s, pkt[:])
}

@(private)
_send_slot_assign :: proc(s: ^Session, p: ^Peer) {
    pkt: [2]u8
    pkt[0] = u8(MsgType.SlotAssign)
    pkt[1] = u8(p.slot)
    _send_to_peer(p, pkt[:])
}

@(private)
_send_hello_to :: proc(s: ^Session, p: ^Peer) {
    pkt: [1 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.Hello)
    copy(pkt[1:], s.local_name[:])
    _send_to_peer(p, pkt[:])
}

@(private)
_send_hello_ack :: proc(s: ^Session) {
    pkt: [1 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.HelloAck)
    copy(pkt[1:], s.local_name[:])
    _send(s, pkt[:])
}

@(private)
_send_roster_name :: proc(pkt_target: ^Peer, slot: int, name: []u8) {
    pkt: [2 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.RosterName)
    pkt[1] = u8(slot)
    copy(pkt[2:], name)
    _send_to_peer(pkt_target, pkt[:])
}

@(private)
_broadcast_roster_name :: proc(s: ^Session, slot: int, name: []u8, except: ^Peer = nil) {
    pkt: [2 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.RosterName)
    pkt[1] = u8(slot)
    copy(pkt[2:], name)
    _broadcast(s, pkt[:], true, except)
}

@(private)
_broadcast_roster_char_data :: proc(s: ^Session, slot: int, data: []u8, except: ^Peer = nil) {
    pkt := make([]u8, 2 + len(data), context.temp_allocator)
    pkt[0] = u8(MsgType.RosterCharData)
    pkt[1] = u8(slot)
    copy(pkt[2:], data)
    _broadcast(s, pkt, true, except)
}

@(private)
_broadcast_roster_left :: proc(s: ^Session, slot: int) {
    pkt: [2]u8
    pkt[0] = u8(MsgType.RosterLeft)
    pkt[1] = u8(slot)
    _broadcast(s, pkt[:])
}

@(private)
_send_known_roster_to :: proc(s: ^Session, p: ^Peer) {
    _send_roster_name(p, 0, s.local_name[:])
    for &other in s.peers {
        if !other.active || other.slot == p.slot { continue }
        entry := &s.roster[other.slot]
        if entry.known {
            _send_roster_name(p, other.slot, entry.name[:])
        }
        if entry.char_ready {
            pkt := make([]u8, 2 + entry.char_len, context.temp_allocator)
            pkt[0] = u8(MsgType.RosterCharData)
            pkt[1] = u8(other.slot)
            copy(pkt[2:], entry.char_data[:entry.char_len])
            _send_to_peer(p, pkt)
        }
    }
}

@(private)
_handle_client :: proc(s: ^Session, data: []u8) {
    if len(data) == 0 { return }
    s.no_recv_timer = 0
    switch MsgType(data[0]) {
    case .SlotAssign:
        if len(data) >= 2 {
            s.local_slot = int(data[1])
            fmt.printf("[p2p] assigned slot %d\n", s.local_slot)
        }
    case .Hello:
        if s.state == .Connected && len(data) >= 1 + NAME_SIZE {
            _send_hello_ack(s)
        }
    case .HelloAck:
        if s.state == .Connected && len(data) >= 1 + NAME_SIZE {
            s.peer_ready = true
        }
    case .Ready:
        s.peer_ready = true
    case .EditorOp:
        _handle_editor_op(s, data[1:])
    case .LevelLoad:
        _handle_level_load_msg(s, data[1:])
    case .EditorModOp:
        _handle_editor_mod_op(s, data[1:])
    case .CharacterData:
        payload := data[1:]
        n := min(len(payload), MAX_SAVE_BYTES)
        entry := &s.roster[0]
        copy(entry.char_data[:n], payload[:n])
        entry.char_len   = n
        entry.char_ready = true
        entry.known      = true
        fmt.printf("[p2p] received CharacterData (%d bytes)\n", n)
    case .HostSnapshot:
        _handle_host_snapshot(s, data[1:])
    case .RaidResult:
        _handle_raid_result(s, data[1:])
    case .RosterName:
        if len(data) >= 2 + NAME_SIZE {
            slot := int(data[1])
            if slot >= 0 && slot < MAX_PLAYERS {
                entry := &s.roster[slot]
                copy(entry.name[:], data[2:2+NAME_SIZE])
                entry.known = true
                if slot == 0 { s.peer_ready = true }
            }
        }
    case .RosterCharData:
        if len(data) >= 2 {
            slot := int(data[1])
            if slot >= 0 && slot < MAX_PLAYERS {
                payload := data[2:]
                n := min(len(payload), MAX_SAVE_BYTES)
                entry := &s.roster[slot]
                copy(entry.char_data[:n], payload[:n])
                entry.char_len   = n
                entry.char_ready = true
                entry.known      = true
            }
        }
    case .RosterLeft:
        if len(data) >= 2 {
            slot := int(data[1])
            if slot >= 0 && slot < MAX_PLAYERS {
                s.roster[slot] = {}
            }
        }
    case .ClientInput:
    }
}

@(private)
_handle_host :: proc(s: ^Session, p: ^Peer, data: []u8) {
    if len(data) == 0 { return }
    p.no_recv_timer = 0
    switch MsgType(data[0]) {
    case .Hello:
        if len(data) >= 1 + NAME_SIZE {
            entry := &s.roster[p.slot]
            copy(entry.name[:], data[1:1+NAME_SIZE])
            entry.known = true
            _send_roster_name(p, 0, s.local_name[:])
            pkt: [1 + NAME_SIZE]u8
            pkt[0] = u8(MsgType.HelloAck)
            copy(pkt[1:], s.local_name[:])
            _send_to_peer(p, pkt[:])
            _broadcast_roster_name(s, p.slot, entry.name[:], p)
            p.peer_ready = true
        }
    case .HelloAck:
        p.peer_ready = true
    case .Ready:
        p.peer_ready = true
    case .EditorOp:
        _handle_editor_op(s, data[1:])
    case .LevelLoad:
        _handle_level_load_msg(s, data[1:])
    case .EditorModOp:
        _handle_editor_mod_op(s, data[1:])
    case .CharacterData:
        payload := data[1:]
        n := min(len(payload), MAX_SAVE_BYTES)
        entry := &s.roster[p.slot]
        copy(entry.char_data[:n], payload[:n])
        entry.char_len   = n
        entry.char_ready = true
        entry.known      = true
        fmt.printf("[p2p] received CharacterData (%d bytes) from slot %d\n", n, p.slot)
        _broadcast_roster_char_data(s, p.slot, payload[:n], p)
    case .ClientInput:
        f, ok := decode_frame(data[1:])
        if ok {
            p.latest_client_input = f
            p.has_client_input    = true
        }
    case .HostSnapshot, .RaidResult, .RosterName, .RosterCharData, .RosterLeft, .SlotAssign:
    }
}
