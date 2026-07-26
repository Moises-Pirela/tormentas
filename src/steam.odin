package main

import sw  "../steamworks"
import p2p "p2p"
import "core:fmt"
import "core:strconv"

g_steam_ok:           bool
g_steam_pipe:         sw.HSteamPipe
g_steam_lobby_id:     sw.CSteamID
g_pending_join_lobby: sw.CSteamID

// A resolved, accept-able co-op invitation, surfaced as an on-screen prompt so the
// player can join from anywhere rather than only while sitting in the hub.
g_invite_pending:   bool
g_invite_host_id:   sw.CSteamID
g_invite_host_name: [64]u8
g_invite_name_len:  int

@(private = "file")
g_create_lobby_call: sw.SteamAPICall

SteamFriend :: struct {
    steam_id: sw.CSteamID,
    name:     string,
    in_game:  bool,
}

steam_init :: proc() -> bool {
    err: sw.SteamErrMsg
    res := sw.InitEx(&err)
    if res != .OK {
        fmt.eprintf("[steam] init failed: %s\n", cstring(&err[0]))
        return false
    }
    sw.ManualDispatch_Init()
    g_steam_pipe = sw.GetHSteamPipe()
    g_steam_ok   = true
    fmt.println("[steam] initialized, local ID:", steam_get_local_id())
    return true
}

steam_shutdown :: proc() {
    if !g_steam_ok { return }
    steam_lobby_leave()
    sw.Shutdown()
    g_steam_ok            = false
    g_steam_pipe          = 0
    g_pending_join_lobby  = 0
}

steam_run_callbacks :: proc() {
    if !g_steam_ok { return }
    sw.ManualDispatch_RunFrame(g_steam_pipe)
    cb: sw.CallbackMsg
    for sw.ManualDispatch_GetNextCallback(g_steam_pipe, &cb) {
        defer sw.ManualDispatch_FreeLastCallback(g_steam_pipe)
        #partial switch cb.iCallback {
        case .GameLobbyJoinRequested:
            // Accepting an invite only tells us *which* lobby to join — we must
            // actually enter it before its data (host_id) becomes readable. The
            // real join is kicked off in the LobbyEnter callback below.
            req := (^sw.GameLobbyJoinRequested)(cb.pubParam)
            fmt.printf("[steam] lobby join requested: %d\n", u64(req.steamIDLobby))
            sw.Matchmaking_JoinLobby(sw.Matchmaking(), req.steamIDLobby)

        case .LobbyEnter:
            ev    := (^sw.LobbyEnter)(cb.pubParam)
            lobby := sw.CSteamID(ev.ulSteamIDLobby)
            // The host also gets LobbyEnter for the lobby it created — skip that one.
            if lobby != g_steam_lobby_id {
                g_pending_join_lobby = lobby
                fmt.printf("[steam] entered lobby: %d\n", u64(lobby))
            }

        case .SteamNetConnectionStatusChangedCallback:
            ev := (^sw.SteamNetConnectionStatusChangedCallback)(cb.pubParam)
            p2p.session_on_conn_changed(&g_session, ev)

        case .SteamAPICallCompleted:
            completed := (^sw.SteamAPICallCompleted)(cb.pubParam)
            if g_create_lobby_call != 0 && completed.hAsyncCall == g_create_lobby_call {
                result: sw.LobbyCreated
                failed: bool
                ok := sw.ManualDispatch_GetAPICallResult(
                    g_steam_pipe, completed.hAsyncCall,
                    &result, i32(size_of(sw.LobbyCreated)), .LobbyCreated, &failed)
                if ok && !failed && result.eResult == .OK {
                    g_steam_lobby_id = sw.CSteamID(result.ulSteamIDLobby)
                    local_id := steam_get_local_id()
                    id_str: [32]u8
                    s := fmt.bprintf(id_str[:31], "%d", u64(local_id))
                    id_str[len(s)] = 0
                    sw.Matchmaking_SetLobbyData(sw.Matchmaking(), g_steam_lobby_id,
                        "host_id", cstring(&id_str[0]))
                    fmt.printf("[steam] lobby created: %d\n", u64(g_steam_lobby_id))
                }
                g_create_lobby_call = 0
            }
        }
    }
}

steam_get_local_id :: proc() -> sw.CSteamID {
    if !g_steam_ok { return 0 }
    return sw.User_GetSteamID(sw.User())
}

steam_friend_name :: proc(id: sw.CSteamID) -> string {
    if !g_steam_ok { return "" }
    return string(sw.Friends_GetFriendPersonaName(sw.Friends(), id))
}

steam_get_friends :: proc(allocator := context.temp_allocator) -> []SteamFriend {
    if !g_steam_ok { return nil }
    fi    := sw.Friends()
    count := sw.Friends_GetFriendCount(fi, i32(sw.EFriendFlags.Immediate))
    if count <= 0 { return nil }
    buf := make([]SteamFriend, count, context.temp_allocator)
    n   := 0
    for i in 0..<count {
        id    := sw.Friends_GetFriendByIndex(fi, i, i32(sw.EFriendFlags.Immediate))
        state := sw.Friends_GetFriendPersonaState(fi, id)
        if state == .Offline { continue }
        buf[n] = {
            steam_id = id,
            name     = string(sw.Friends_GetFriendPersonaName(fi, id)),
            in_game  = state != .Offline,
        }
        n += 1
    }
    out := make([]SteamFriend, n, allocator)
    copy(out, buf[:n])
    return out
}

steam_lobby_create :: proc() {
    if !g_steam_ok || g_create_lobby_call != 0 { return }
    g_create_lobby_call = sw.Matchmaking_CreateLobby(sw.Matchmaking(), .FriendsOnly, 2)
}

steam_lobby_invite :: proc(friend_id: sw.CSteamID) {
    if !g_steam_ok || g_steam_lobby_id == 0 { return }
    sw.Matchmaking_InviteUserToLobby(sw.Matchmaking(), g_steam_lobby_id, friend_id)
}

steam_lobby_leave :: proc() {
    if !g_steam_ok || g_steam_lobby_id == 0 { return }
    sw.Matchmaking_LeaveLobby(sw.Matchmaking(), g_steam_lobby_id)
    g_steam_lobby_id = 0
}

steam_lobby_get_host_id :: proc(lobby_id: sw.CSteamID) -> sw.CSteamID {
    if !g_steam_ok { return 0 }
    host_str := sw.Matchmaking_GetLobbyData(sw.Matchmaking(), lobby_id, "host_id")
    if host_str == nil || len(host_str) == 0 { return 0 }
    val, ok := strconv.parse_uint(string(host_str), 10)
    if !ok { return 0 }
    return sw.CSteamID(val)
}
