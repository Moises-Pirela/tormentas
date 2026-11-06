package main

hud_gold_display :: proc(w: ^World) -> int {
    if g_playing_state == .Gameplay && world_is_valid(w, w.player_id) &&
       world_has_component(w, w.player_id, .Wallet) {
        return comp_get(w, w.player_id, .Wallet, WalletComp).gold
    }
    return local_stash().gold
}

bank_wallet_gold :: proc(w: ^World, pid: int) {
    if !world_is_valid(w, pid)                { return }
    if !world_has_component(w, pid, .Wallet) { return }
    wallet := comp_get(w, pid, .Wallet, WalletComp)
    if wallet.gold <= 0 { return }
    local_stash().gold += wallet.gold
    wallet.gold = 0
}
