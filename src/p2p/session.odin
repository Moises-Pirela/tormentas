package p2p

import "core:net"
import "core:fmt"

// =============================================================================
// Session — UDP peer-to-peer session using Odin's core:net.
// No external C library required.
//
// Handshake (simple stop-and-wait over UDP):
//   Host:   bind → wait for Hello → send HelloAck → Connected
//   Client: send Hello (retry every 0.5 s) → recv HelloAck → send Ready → Connected
//
// Once Connected, both sides exchange InputBundles every sim tick.
// =============================================================================

RECV_BUF_SIZE        :: 2048
HANDSHAKE_RESEND_SEC :: f32(0.5)
BUNDLE_HISTORY       :: 3         // past frames bundled per send for redundancy
MAX_STALL_SEC        :: f32(0.1)  // stall warning threshold (seconds)
DISCONNECT_TIMEOUT   :: f32(6.0)  // seconds of silence before declaring disconnect

MsgType :: enum u8 {
    Hello        = 1,   // client → host
    HelloAck     = 2,   // host   → client
    Ready        = 3,   // client → host (after HelloAck)
    InputBundle  = 4,   // both   → both (unreliable, frequent)
    EditorOp     = 5,   // both   → both (unreliable, editor tile delta)
    LevelLoad    = 6,   // both   → both (unreliable, load level N from disk)
    EditorModOp  = 7,   // both   → both (unreliable, inspector field edit)
}

SessionState :: enum {
    Offline,
    Hosting,      // bound; waiting for Hello
    Connecting,   // sending Hello; waiting for HelloAck
    Connected,
    Disconnected, // peer went silent; triggers return to menu
}

// NAME_SIZE is the fixed wire-length of the player-name field in Hello/HelloAck.
// Matches PLAYER_NAME_MAX+1 from the main package.
NAME_SIZE :: 25

Session :: struct {
    state:        SessionState,
    socket:       net.UDP_Socket,
    peer_ep:      net.Endpoint,   // remote address + port (filled on connect)
    local_slot:   int,            // 0 = host, 1 = client
    peer_ready:   bool,           // remote sent Ready
    resend_timer: f32,            // seconds since last Hello resend
    buf:          InputBuffer,
    cur_tick:     u32,

    // Player names — set local_name before handshaking; remote_name is filled
    // once the peer's Hello/HelloAck is received.
    local_name:  [NAME_SIZE]u8,
    remote_name: [NAME_SIZE]u8,

    // Editor sync queues — filled by _handle, drained by session_drain_editor*.
    editor_ops:          [dynamic]EditorOp,
    editor_mod_ops:      [dynamic]EditorModOp,
    pending_level_load:  int,     // 0 = none; > 0 = level number to load

    // Disconnect detection: time since any packet was last received.
    // Reset to 0 on every _handle call; if it exceeds DISCONNECT_TIMEOUT
    // while Connected, state transitions to Disconnected.
    no_recv_timer: f32,
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

// Bind to 0.0.0.0:port and wait for an incoming client.
session_host :: proc(s: ^Session, port: int) -> bool {
    sock, err := net.make_unbound_udp_socket(.IP4)
    if err != nil {
        fmt.eprintln("[net] socket:", err)
        return false
    }
    ep := net.Endpoint{ address = net.IP4_Address{0, 0, 0, 0}, port = port }
    if berr := net.bind(sock, ep); berr != nil {
        fmt.eprintln("[net] bind:", berr)
        net.close(sock)
        return false
    }
    if serr := net.set_blocking(sock, false); serr != nil {
        fmt.eprintln("[net] set_blocking:", serr)
        net.close(sock)
        return false
    }
    s.socket     = sock
    s.local_slot = 0
    s.state      = .Hosting
    fmt.printf("[net] hosting on :%d — waiting for peer\n", port)
    return true
}

// Create an unbound socket and start sending Hello to host_ip:port.
session_join :: proc(s: ^Session, host_ip: string, port: int) -> bool {
    addr := net.parse_address(host_ip)
    if addr == nil {
        fmt.eprintln("[net] invalid address:", host_ip)
        return false
    }
    sock, err := net.make_unbound_udp_socket(.IP4)
    if err != nil {
        fmt.eprintln("[net] socket:", err)
        return false
    }
    if serr := net.set_blocking(sock, false); serr != nil {
        fmt.eprintln("[net] set_blocking:", serr)
        net.close(sock)
        return false
    }
    s.socket     = sock
    s.peer_ep    = net.Endpoint{ address = addr, port = port }
    s.local_slot = 1
    s.state      = .Connecting
    _send_hello(s)   // immediate first Hello (carries local_name)
    fmt.printf("[net] connecting to %s:%d\n", host_ip, port)
    return true
}

session_shutdown :: proc(s: ^Session) {
    if s.state == .Offline { return }
    net.close(s.socket)
    delete(s.editor_ops)
    delete(s.editor_mod_ops)
    s^ = {}
}

session_poll :: proc(s: ^Session, dt: f32) {
    if s.state == .Offline { return }

    if s.state == .Connecting {
        s.resend_timer += dt
        if s.resend_timer >= HANDSHAKE_RESEND_SEC {
            s.resend_timer = 0
            _send_hello(s)
        }
    }

    // Drain receive buffer
    buf: [RECV_BUF_SIZE]u8
    for {
        n, from_ep, err := net.recv_udp(s.socket, buf[:])
        if err != nil || n == 0 { break }
        _handle(s, buf[:n], from_ep)
    }

    if s.state == .Connected {
        s.no_recv_timer += dt
        if s.no_recv_timer >= DISCONNECT_TIMEOUT {
            fmt.println("[net] peer timed out — marking disconnected")
            s.state = .Disconnected
        }
    }
}

session_send_inputs :: proc(s: ^Session, frames: []InputFrame) {
    if s.state != .Connected || s.peer_ep.port == 0 || len(frames) == 0 { return }
    pkt := make([]u8, 1 + len(frames)*INPUT_FRAME_SIZE, context.temp_allocator)
    pkt[0] = u8(MsgType.InputBundle)
    for f, i in frames {
        encode_frame(f, pkt[1 + i*INPUT_FRAME_SIZE:])
    }
    net.send_udp(s.socket, pkt, s.peer_ep)
}

session_is_online        :: proc(s: ^Session) -> bool { return s.state == .Connected }
session_is_disconnected  :: proc(s: ^Session) -> bool { return s.state == .Disconnected }

@(private)
_send :: proc(s: ^Session, data: []u8) {
    if s.peer_ep.port == 0 { return }
    net.send_udp(s.socket, data, s.peer_ep)
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
    net.send_udp(s.socket, pkt[:], s.peer_ep)
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
_handle :: proc(s: ^Session, data: []u8, from: net.Endpoint) {
    if len(data) == 0 { return }
    s.no_recv_timer = 0   // any packet resets the disconnect watchdog
    switch MsgType(data[0]) {
    case .Hello:
        if s.state == .Hosting {
            s.peer_ep = from
            if len(data) >= 1 + NAME_SIZE {
                copy(s.remote_name[:], data[1:1 + NAME_SIZE])
            }
            s.state = .Connected
            _prefill_delay(s)
            _send_hello_ack(s)   
            fmt.println("[net] peer connected, sent HelloAck")
        }
    case .HelloAck:
        if s.state == .Connecting {
            s.peer_ep = from
            if len(data) >= 1 + NAME_SIZE {
                copy(s.remote_name[:], data[1:1 + NAME_SIZE])
            }
            s.state = .Connected
            _prefill_delay(s)
            net.send_udp(s.socket, []u8{u8(MsgType.Ready)}, s.peer_ep)
            fmt.println("[net] received HelloAck, sent Ready — connected")
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
    }
}
