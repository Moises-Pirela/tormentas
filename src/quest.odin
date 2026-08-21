package main

QuestID :: enum u8 {
    SurvivorsMark,
    TheHorde,
    Aberration,
    Bloodlines,
    TheDeepRun,
    ElitePredator,
    PerfectRun,
    FinalForm,
}

QUEST_COUNT      :: int(QuestID.FinalForm) + 1
QUEST_FLASH_TIME :: f32(4.0)

QuestDef :: struct {
    title_key:     LocKey,
    lore_key:      LocKey,
    obj_key:       LocKey,
    reward_stats:  int,
    reward_gold:   int,
    reward_serums: int,
}

QUEST_DEFS := [QUEST_COUNT]QuestDef{
    { .QUEST_SURVIVORS_MARK_TITLE,  .QUEST_SURVIVORS_MARK_LORE,  .QUEST_SURVIVORS_MARK_OBJ,  1, 150, 0 },
    { .QUEST_THE_HORDE_TITLE,       .QUEST_THE_HORDE_LORE,       .QUEST_THE_HORDE_OBJ,       1, 100, 0 },
    { .QUEST_ABERRATION_TITLE,      .QUEST_ABERRATION_LORE,      .QUEST_ABERRATION_OBJ,       2, 200, 3 },
    { .QUEST_BLOODLINES_TITLE,      .QUEST_BLOODLINES_LORE,      .QUEST_BLOODLINES_OBJ,       1, 250, 0 },
    { .QUEST_THE_DEEP_RUN_TITLE,    .QUEST_THE_DEEP_RUN_LORE,    .QUEST_THE_DEEP_RUN_OBJ,    1, 300, 2 },
    { .QUEST_ELITE_PREDATOR_TITLE,  .QUEST_ELITE_PREDATOR_LORE,  .QUEST_ELITE_PREDATOR_OBJ,  2,   0, 3 },
    { .QUEST_PERFECT_RUN_TITLE,     .QUEST_PERFECT_RUN_LORE,     .QUEST_PERFECT_RUN_OBJ,     1, 500, 0 },
    { .QUEST_FINAL_FORM_TITLE,      .QUEST_FINAL_FORM_LORE,      .QUEST_FINAL_FORM_OBJ,      3,   0, 5 },
}

g_quest_completed:   [MAX_PLAYERS]u8

g_quest_flash_timer: f32
g_quest_flash_title: cstring

local_quest_completed :: proc() -> ^u8 {
    return &g_quest_completed[g_session.local_slot]
}

quest_is_done :: proc(id: QuestID) -> bool {
    return (local_quest_completed()^ >> u8(id)) & 1 == 1
}

quest_mark_done :: proc(id: QuestID) {
    local_quest_completed()^ |= (1 << u8(id))
}

quest_progress :: proc(id: QuestID, w: ^World) -> (current, target: int) {
    ls := g_lifetime_stats
    switch id {
    case .SurvivorsMark:
        return int(ls.successful_raids), 1
    case .TheHorde:
        return int(ls.enemies_killed), 30
    case .Aberration:
        return int(ls.bosses_killed), 1
    case .Bloodlines:
        if world_is_valid(w, w.player_id) &&
           world_has_component(w, w.player_id, .MutationContainer) {
            mc := comp_get(w, w.player_id, .MutationContainer, MutationContainerComp)
            return mc.entity_count, 5
        }
        return 0, 5
    case .TheDeepRun:
        return int(ls.deep_extracts), 1
    case .ElitePredator:
        return int(ls.elites_killed), 10
    case .PerfectRun:
        return int(ls.max_extract_gold), 500
    case .FinalForm:
        if world_is_valid(w, w.player_id) &&
           world_has_component(w, w.player_id, .MutationContainer) {
            mc := comp_get(w, w.player_id, .MutationContainer, MutationContainerComp)
            return mc.entity_count, 10
        }
        return 0, 10
    }
    return 0, 1
}

quest_check_all :: proc(w: ^World) {
    last_title: cstring
    any_done := false

    for qi in QuestID {
        if quest_is_done(qi) { continue }
        cur, tgt := quest_progress(qi, w)
        if cur < tgt { continue }

        quest_mark_done(qi)
        def := &QUEST_DEFS[int(qi)]

        pid := w.player_id
        if world_is_valid(w, pid) &&
           world_has_component(w, pid, .Stats) &&
           def.reward_stats > 0 {
            st := comp_get(w, pid, .Stats, StatsComp)
            st.stat_points = st.stat_points + def.reward_stats
            ui_mark_dirty(.Stats)
        }

        if def.reward_gold   > 0 { local_stash().gold   += def.reward_gold }
        if def.reward_serums > 0 { local_stash().serums += def.reward_serums }

        last_title = t(def.title_key)
        any_done   = true
    }

    if any_done {
        g_quest_flash_timer = QUEST_FLASH_TIME
        g_quest_flash_title = last_title
        play_sfx("levelup")
        pid := w.player_id
        if world_is_valid(w, pid) {
            save_player(w, pid)
        }
    }
}
