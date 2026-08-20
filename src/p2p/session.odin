package p2p

import sw  "../../steamworks"
import "core:fmt"

HANDSHAKE_RESEND_SEC :: f32(0.5)
BUNDLE_HISTORY       :: 3
MAX_STALL_SEC        :: f32(0.1)
DISCONNECT_TIMEOUT   :: f32(6.0)
MAX_SAVE_BYTES       :: 65536

MsgType :: enum u8 {
    Hello         = 1,
    HelloAck      = 2,
    Ready         = 3,
    InputBundle   = 4,
    EditorOp      = 5,
    LevelLoad     = 6,
    EditorModOp   = 7,
    CharacterData = 8,
}

SessionState :: enum {
    Offline,
    Hosting,
    Connecting,
    Connected,
    Disconnected,
}

NAME_SIZE :: 25

Session :: struct {
    state:       SessionState,
    conn:        sw.HSteamNetConnection,
    listen_sock: sw.HSteamListenSocket,
    local_slot:  int,
    peer_ready:  bool,
    buf:         InputBuffer,
    cur_tick:    u32,

    local_name:  [NAME_SIZE]u8,
    remote_name: [NAME_SIZE]u8,

    editor_ops:         [dynamic]EditorOp,
    editor_mod_ops:     [dynamic]EditorModOp,
    pending_level_load: int,

    no_recv_timer: f32,

    remote_char_data:  [MAX_SAVE_BYTES]u8,
    remote_char_len:   int,
    remote_char_ready: bool,

    char_data_sent: bool,
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
    fmt.println("[p2p] hosting via Steam P2P — waiting for peer")
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
    s.local_slot = 1
    s.state      = .Connecting
    fmt.printf("[p2p] connecting to %d via Steam P2P\n", u64(host_steam_id))
    return true
}

session_shutdown :: proc(s: ^Session) {
    if s.state == .Offline { return }
    socks := sw.NetworkingSockets_SteamAPI()
    if s.conn != sw.HSteamNetConnection_Invalid {
        sw.NetworkingSockets_CloseConnection(socks, s.conn, 0, nil, false)
    }
    if s.listen_sock != 0 {
        sw.NetworkingSockets_CloseListenSocket(socks, s.listen_sock)
    }
    delete(s.editor_ops)
    delete(s.editor_mod_ops)
    s^ = {}
}

session_poll :: proc(s: ^Session, dt: f32) {
    if s.state == .Offline { return }

    if s.conn == sw.HSteamNetConnection_Invalid { return }
    socks := sw.NetworkingSockets_SteamAPI()

    msgs: [16]^sw.SteamNetworkingMessage
    for {
        n := sw.NetworkingSockets_ReceiveMessagesOnConnection(socks, s.conn, &msgs[0], 16)
        if n <= 0 { break }
        for i in 0..<n {
            msg  := msgs[i]
            data := (cast([^]u8)msg.pData)[:msg.cbSize]
            _handle(s, data)
            msg.pfnRelease(msg)
        }
    }

    if s.state == .Connected {
        s.no_recv_timer += dt
        if s.no_recv_timer >= DISCONNECT_TIMEOUT {
            fmt.println("[p2p] peer timed out — marking disconnected")
            s.state = .Disconnected
        }
    }
}

session_on_conn_changed :: proc(s: ^Session, ev: ^sw.SteamNetConnectionStatusChangedCallback) {
    socks := sw.NetworkingSockets_SteamAPI()
    switch ev.info.eState {
    case .Connecting:

        if ev.eOldState == .None && s.listen_sock != 0 &&
           ev.info.hListenSocket == s.listen_sock {
            if sw.NetworkingSockets_AcceptConnection(socks, ev.hConn) == .OK {
                s.conn = ev.hConn
                fmt.println("[p2p] accepted incoming connection")
            } else {
                sw.NetworkingSockets_CloseConnection(socks, ev.hConn, 0, nil, false)
            }
        }
    case .Connected:
        if ev.hConn == s.conn &&
           (s.state == .Hosting || s.state == .Connecting) {
            s.state = .Connected
            _prefill_delay(s)
            _send_hello(s)
            fmt.println("[p2p] connection established")
        }
    case .ClosedByPeer, .ProblemDetectedLocally:
        if ev.hConn == s.conn && s.state != .Offline {
            fmt.printf("[p2p] connection closed: %v\n", ev.info.eState)
            s.state = .Disconnected
        }
    case .None, .FindingRoute, .FinWait, .Linger, .Dead, ._Force32Bit:
    }
}

session_send_inputs :: proc(s: ^Session, frames: []InputFrame) {
    if s.state != .Connected || s.conn == sw.HSteamNetConnection_Invalid ||
       len(frames) == 0 { return }
    pkt := make([]u8, 1 + len(frames)*INPUT_FRAME_SIZE, context.temp_allocator)
    pkt[0] = u8(MsgType.InputBundle)
    for f, i in frames {
        encode_frame(f, pkt[1 + i*INPUT_FRAME_SIZE:])
    }
    _send(s, pkt, false)
}

session_send_char_data :: proc(s: ^Session, data: []u8) {
    if s.state != .Connected || len(data) == 0 { return }
    pkt := make([]u8, 1 + len(data), context.temp_allocator)
    pkt[0] = u8(MsgType.CharacterData)
    copy(pkt[1:], data)
    _send(s, pkt)
}

session_is_online       :: proc(s: ^Session) -> bool { return s.state == .Connected }
session_is_disconnected :: proc(s: ^Session) -> bool { return s.state == .Disconnected }

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
_send_hello :: proc(s: ^Session) {
    pkt: [1 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.Hello)
    copy(pkt[1:], s.local_name[:])
    _send(s, pkt[:])
}

@(private)
_send_hello_ack :: proc(s: ^Session) {
    pkt: [1 + NAME_SIZE]u8
    pkt[0] = u8(MsgType.HelloAck)
    copy(pkt[1:], s.local_name[:])
    _send(s, pkt[:])
}

@(private)
_prefill_delay :: proc(s: ^Session) {
    for t in 0..<INPUT_DELAY {
        for p in 0..<MAX_PLAYERS {
            input_buf_put(&s.buf, InputFrame{ tick = u32(t), peer = u8(p) })
        }
    }
}

@(private)
_handle :: proc(s: ^Session, data: []u8) {
    if len(data) == 0 { return }
    s.no_recv_timer = 0
    switch MsgType(data[0]) {
    case .Hello:
        if s.state == .Connected && len(data) >= 1 + NAME_SIZE {
            copy(s.remote_name[:], data[1:1 + NAME_SIZE])
            _send_hello_ack(s)
        }
    case .HelloAck:
        if s.state == .Connected && len(data) >= 1 + NAME_SIZE {
            copy(s.remote_name[:], data[1:1 + NAME_SIZE])
            s.peer_ready = true
        }
    case .Ready:
        s.peer_ready = true
    case .InputBundle:
        payload := data[1:]
        n := len(payload) / INPUT_FRAME_SIZE
        for i in 0..<n {
            f, ok := decode_frame(payload[i*INPUT_FRAME_SIZE : (i+1)*INPUT_FRAME_SIZE])
            if ok { input_buf_put(&s.buf, f) }
        }
    case .EditorOp:
        _handle_editor_op(s, data[1:])
    case .LevelLoad:
        _handle_level_load_msg(s, data[1:])
    case .EditorModOp:
        _handle_editor_mod_op(s, data[1:])
    case .CharacterData:
        payload := data[1:]
        n := min(len(payload), MAX_SAVE_BYTES)
        copy(s.remote_char_data[:n], payload[:n])
        s.remote_char_len   = n
        s.remote_char_ready = true
        fmt.printf("[p2p] received CharacterData (%d bytes)\n", n)
    }
}
