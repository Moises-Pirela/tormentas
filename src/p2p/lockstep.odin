package p2p

import "core:fmt"

TickResult :: enum {
    Ready,    
    Stalled,  
    Offline,  
}

HistoryBuf :: struct {
    frames: [BUNDLE_HISTORY]InputFrame,
    count:  int,
}

history_push :: proc(h: ^HistoryBuf, f: InputFrame) {
    for i := min(h.count, BUNDLE_HISTORY-1); i > 0; i -= 1 {
        h.frames[i] = h.frames[i-1]
    }
    h.frames[0] = f
    h.count = min(h.count + 1, BUNDLE_HISTORY)
}

history_slice :: proc(h: ^HistoryBuf) -> []InputFrame {
    return h.frames[:h.count]
}

lockstep_advance :: proc(
    s:         ^Session,
    local:     InputFrame,
    hist:      ^HistoryBuf,
    stall_acc: ^f32,
    dt:        f32,
) -> TickResult {
    if !session_is_online(s) { return .Offline }

    future      := local
    future.peer  = u8(s.local_slot)
    future.tick  = s.cur_tick + INPUT_DELAY
    input_buf_put(&s.buf, future)

    history_push(hist, future)
    session_send_inputs(s, history_slice(hist))

    _, has_local  := input_buf_get(&s.buf, s.local_slot,       s.cur_tick)
    _, has_remote := input_buf_get(&s.buf, 1 - s.local_slot,   s.cur_tick)

    if !has_local || !has_remote {
        stall_acc^ += dt
        if stall_acc^ > MAX_STALL_SEC {
            fmt.printf("[net] stall at tick %d — waiting %.0f ms\n",
                s.cur_tick, stall_acc^ * 1000)
        }
        return .Stalled
    }

    stall_acc^ = 0
    return .Ready
}

lockstep_consume :: proc(s: ^Session) -> (local_frame, remote_frame: InputFrame) {
    local_frame,  _ = input_buf_get(&s.buf, s.local_slot,     s.cur_tick)
    remote_frame, _ = input_buf_get(&s.buf, 1-s.local_slot,   s.cur_tick)
    input_buf_evict(&s.buf, s.cur_tick)
    s.cur_tick += 1
    return
}
