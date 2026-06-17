package main

import "core:os"
import "core:strings"
import "core:fmt"


Language :: enum u8 { EN, ES, PT }

LANG_COUNT :: 3

g_lang: Language = .EN


LocKey :: enum {

    MENU_TITLE,
    MENU_SUBTITLE,
    MENU_DISCONNECTED,
    MENU_SELECT_CHARACTER,
    MENU_NAME_CHARACTER,
    MENU_SLOT_NEW,
    MENU_SLOT_EMPTY,
    MENU_BTN_CREATE,
    MENU_BTN_CANCEL,
    MENU_BTN_PLAY,
    MENU_BTN_CONFIRM,
    MENU_BTN_DELETE,
    MENU_BTN_SINGLEPLAYER,
    MENU_BTN_HOST,
    MENU_BTN_JOIN,
    MENU_HOST_IP_LABEL,
    MENU_BTN_CONNECT,
    MENU_BTN_BACK,
    MENU_WAITING,
    MENU_CONNECTING,
    MENU_ESC_CANCEL,
    MENU_CHAR_DEFAULT,
    MENU_BTN_SETTINGS,
    MENU_BTN_EXIT,

    HUD_EXTRACT,
    HUD_LOOT_FILTER,
    HUD_FILTER_ALL,
    HUD_FILTER_RARE,
    HUD_FILTER_EPIC,
    HUD_FILTER_LEGENDARY,
    HUD_FILTER_UNIQUE,
    HUD_RAID_TIMER,
    HUD_WARNING,
    HUD_BOSS_APPROACHES,
    HUD_ITEM_ACTIVE,
    HUD_ITEM_PASSIVE,
    HUD_LEVELUP,
    HUD_STATPOINT,

    PAUSE_TITLE,
    PAUSE_BTN_RESUME,
    PAUSE_BTN_KEYBINDS,
    PAUSE_BTN_QUIT,

    SETTINGS_TITLE,
    SETTINGS_RESOLUTION,
    SETTINGS_WINDOW_MODE,
    SETTINGS_BORDERLESS,
    SETTINGS_WINDOWED,
    SETTINGS_VOLUME,
    SETTINGS_SFX,
    SETTINGS_MUSIC,
    SETTINGS_AMBIENCE,
    SETTINGS_VOICE,
    SETTINGS_LANGUAGE,
    SETTINGS_BTN_KEYBINDS,
    SETTINGS_BTN_CLOSE,
    SETTINGS_BTN_EXIT,

    LANG_EN,
    LANG_ES,
    LANG_PT,

    KEYBINDS_TITLE,
    KEYBINDS_SECTION_GAMEPLAY,
    KEYBINDS_SECTION_UI,
    KEYBINDS_PRESS_KEY,
    KEYBINDS_BTN_RESET,
    KEYBINDS_BTN_CLOSE,
    KEYBINDS_ESC_CANCEL,

    INV_TITLE,
    INV_ARMOR,
    INV_SLOT_HEAD,
    INV_SLOT_CHEST,
    INV_SLOT_BOOTS,
    INV_WEAPONS,
    INV_SLOT_WEAPON,
    INV_SLOT_OFFHAND,
    INV_ABILITIES,
    INV_BACKPACK,
    INV_BTN_CLOSE,
    INV_UNEQUIPPED,

    STATS_TITLE,
    STATS_STRENGTH,
    STATS_DEXTERITY,
    STATS_SCIENCE,
    STATS_HP_BONUS,
    STATS_SPEED_BONUS,
    STATS_ENERGY_BONUS,
    STATS_SECTION,
    STATS_HISTORY,
    STATS_RAIDS,
    STATS_KILLS,
    STATS_DEATHS,
    STATS_BEST_EXTRACT,
    STATS_BTN_CLOSE,

    MUT_INTERACT,
    MUT_BRANCH_CORPUS,
    MUT_BRANCH_SHADOW,
    MUT_BRANCH_VENOM,
    MUT_TITLE,
    MUT_SERUMS,
    MUT_COST,
    MUT_ACQUIRED,
    MUT_CONFLICT,
    MUT_CRAFT_HINT,
    MUT_FOOTER,
    MUT_RESET,

    HUB_INTERACT,
    HUB_LABEL,
    HUB_STASH,
    HUB_LEVEL_SELECT,
    HUB_LEVEL_N,
    HUB_NO_LEVELS,
    HUB_ESC_CANCEL,
    HUB_BTN_RETURN,
    HUB_BTN_RETRY,

    EXTRACT_TITLE,
    EXTRACT_SUBTITLE,
    EXTRACT_GOLD,
    EXTRACT_SERUMS,
    EXTRACT_STASH_TOTAL,

    DEATH_TITLE,
    DEATH_MSG,
    DEATH_STASH,

    SHOP_INTERACT,
    SHOP_TITLE,
    SHOP_GOLD,
    SHOP_SOLD_OUT,
    SHOP_SELL,
    SHOP_ESC_CLOSE,

    ABILITY_VENDOR_INTERACT,
    ABILITY_VENDOR_SUBTITLE,

    STASH_INTERACT,
    STASH_TITLE,
    STASH_DEPOSIT_ALL,

    ITEM_CORRUPTED_RELIQUARY_NAME,
    ITEM_CORRUPTED_RELIQUARY_DESC,
    ITEM_LEATHER_CARAPACE_NAME,
    ITEM_LEATHER_CARAPACE_DESC,
    ITEM_IRON_BULWARK_NAME,
    ITEM_IRON_BULWARK_DESC,
    ITEM_BANDOLIER_RIG_NAME,
    ITEM_BANDOLIER_RIG_DESC,
    ITEM_ETHEREAL_SHARD_NAME,
    ITEM_ETHEREAL_SHARD_DESC,
    ITEM_COYOTE_STRIDERS_NAME,
    ITEM_COYOTE_STRIDERS_DESC,
    ITEM_BONE_FETISH_NAME,
    ITEM_BONE_FETISH_DESC,
    ITEM_HAMMERLOCK_PISTOL_NAME,
    ITEM_HAMMERLOCK_PISTOL_DESC,
    ITEM_LIGHTCOIL_REPEATER_NAME,
    ITEM_LIGHTCOIL_REPEATER_DESC,
    ITEM_DRUMFEED_CARBINE_NAME,
    ITEM_DRUMFEED_CARBINE_DESC,
    ITEM_DESERT_MACHETE_NAME,
    ITEM_DESERT_MACHETE_DESC,
    ITEM_WAR_CLEAVER_NAME,
    ITEM_WAR_CLEAVER_DESC,
    ITEM_QUICKFANG_KNIFE_NAME,
    ITEM_QUICKFANG_KNIFE_DESC,
    ITEM_NECROTIC_SERUM_NAME,
    ITEM_NECROTIC_SERUM_DESC,
    ITEM_NECROTIC_SERUM3_NAME,
    ITEM_NECROTIC_SERUM3_DESC,

    INTERACT_OPEN,
    INTERACT_UNLOCK,
    INTERACT_OPENS_ELSEWHERE,
    INTERACT_PULL_LEVER,
    INTERACT_OPEN_CHEST,
    INTERACT_BREAK_CRATE,
    INTERACT_OPEN_LOCKER,
    INTERACT_SEARCH_CABINET,
    INTERACT_READ_DOCUMENT,
    INTERACT_WIND_PHONOGRAPH,
    INTERACT_TAKE_KEY,

    LORE_01_TITLE,
    LORE_01_BODY,
    LORE_02_TITLE,
    LORE_02_BODY,
    LORE_03_TITLE,
    LORE_03_BODY,

    REC_01_TITLE,
    REC_01_TRANSCRIPT,
    REC_02_TITLE,
    REC_02_TRANSCRIPT,
    REC_03_TITLE,
    REC_03_TRANSCRIPT,

    CLASS_SELECT_TITLE,
    CLASS_SELECT_BEGIN,
    CLASS_STARTER_ABILITY,
    CLASS_STARTER_WEAPON,
    CLASS_STAT_STR,
    CLASS_STAT_DEX,
    CLASS_STAT_SCI,

    CLASS_NURSE_NAME,
    CLASS_PR1S_NAME,
    CLASS_SHERIFF_NAME,
    CLASS_SRBRAIN_NAME,

    CLASS_NURSE_TITLE,
    CLASS_PR1S_TITLE,
    CLASS_SHERIFF_TITLE,
    CLASS_SRBRAIN_TITLE,

    CLASS_NURSE_DESC,
    CLASS_PR1S_DESC,
    CLASS_SHERIFF_DESC,
    CLASS_SRBRAIN_DESC,

    CLASS_NURSE_WEAPON,
    CLASS_PR1S_WEAPON,
    CLASS_SHERIFF_WEAPON,
    CLASS_SRBRAIN_WEAPON,

    QUEST_BOARD_NPC_NAME,
    QUEST_BOARD_TITLE,
    QUEST_BOARD_INTERACT,

    QUEST_SURVIVORS_MARK_TITLE,
    QUEST_SURVIVORS_MARK_LORE,
    QUEST_SURVIVORS_MARK_OBJ,

    QUEST_THE_HORDE_TITLE,
    QUEST_THE_HORDE_LORE,
    QUEST_THE_HORDE_OBJ,

    QUEST_ABERRATION_TITLE,
    QUEST_ABERRATION_LORE,
    QUEST_ABERRATION_OBJ,

    QUEST_BLOODLINES_TITLE,
    QUEST_BLOODLINES_LORE,
    QUEST_BLOODLINES_OBJ,

    QUEST_THE_DEEP_RUN_TITLE,
    QUEST_THE_DEEP_RUN_LORE,
    QUEST_THE_DEEP_RUN_OBJ,

    QUEST_ELITE_PREDATOR_TITLE,
    QUEST_ELITE_PREDATOR_LORE,
    QUEST_ELITE_PREDATOR_OBJ,

    QUEST_PERFECT_RUN_TITLE,
    QUEST_PERFECT_RUN_LORE,
    QUEST_PERFECT_RUN_OBJ,

    QUEST_FINAL_FORM_TITLE,
    QUEST_FINAL_FORM_LORE,
    QUEST_FINAL_FORM_OBJ,

    _LOC_COUNT,
}

LOC_KEY_COUNT :: int(LocKey._LOC_COUNT)


@(private = "file")
g_loc: [LANG_COUNT][LOC_KEY_COUNT]cstring


loc_init :: proc() {
    data, ok := os.read_entire_file("data/loc.csv")
    if !ok { return }
    defer delete(data)


    content := string(data)
    lines   := strings.split_lines(content, context.temp_allocator)
    if len(lines) < 2 { return }

    hdr := _loc_csv_split(lines[0], context.temp_allocator)
    col_lang: [16]int
    for i in 0..<16 { col_lang[i] = -1 }
    nc := min(len(hdr), 16)
    for i in 1..<nc {
        switch strings.trim_space(hdr[i]) {
        case "en": col_lang[i] = int(Language.EN)
        case "es": col_lang[i] = int(Language.ES)
        case "pt": col_lang[i] = int(Language.PT)
        }
    }


    for raw_line in lines[1:] {
        line := strings.trim_space(raw_line)
        if len(line) == 0 || line[0] == '#' { continue }

        cols := _loc_csv_split(line, context.temp_allocator)
        if len(cols) < 2 { continue }

        key, found := _loc_key_from_name(strings.trim_space(cols[0]))
        if !found { continue }
        ki := int(key)

        for c in 1..<min(len(cols), nc) {
            li := col_lang[c]
            if li < 0 { continue }
            txt := strings.trim_space(cols[c])
            if txt == "" { continue }

            if g_loc[li][ki] != nil { delete(g_loc[li][ki]) }
            g_loc[li][ki] = strings.clone_to_cstring(txt)
        }
    }
}

loc_destroy :: proc() {
    for l in 0..<LANG_COUNT {
        for k in 0..<LOC_KEY_COUNT {
            if g_loc[l][k] != nil {
                delete(g_loc[l][k])
                g_loc[l][k] = nil
            }
        }
    }
}


@(private = "file")
_loc_csv_split :: proc(line: string, allocator := context.allocator) -> []string {
    result: [dynamic]string
    result.allocator = allocator
    i := 0
    n := len(line)
    for {
        if i >= n { break }
        if line[i] == '"' {
            i += 1
            start := i
            for i < n && line[i] != '"' { i += 1 }
            append(&result, line[start:i])
            if i < n { i += 1 }
            if i < n && line[i] == ',' { i += 1 }
        } else {
            start := i
            for i < n && line[i] != ',' { i += 1 }
            append(&result, line[start:i])
            if i < n { i += 1 }
        }
    }
    return result[:]
}

t :: proc(key: LocKey) -> cstring {
    s := g_loc[int(g_lang)][int(key)]
    if s == nil { s = g_loc[int(Language.EN)][int(key)] }
    if s == nil { return "???" }
    return s
}

tf :: proc(key: LocKey, args: ..any) -> cstring {
    return fmt.ctprintf(string(t(key)), ..args)
}

@(private = "file")
_loc_key_from_name :: proc(name: string) -> (LocKey, bool) {
    switch name {

    case "MENU_TITLE":             return .MENU_TITLE, true
    case "MENU_SUBTITLE":          return .MENU_SUBTITLE, true
    case "MENU_DISCONNECTED":      return .MENU_DISCONNECTED, true
    case "MENU_SELECT_CHARACTER":  return .MENU_SELECT_CHARACTER, true
    case "MENU_NAME_CHARACTER":    return .MENU_NAME_CHARACTER, true
    case "MENU_SLOT_NEW":          return .MENU_SLOT_NEW, true
    case "MENU_SLOT_EMPTY":        return .MENU_SLOT_EMPTY, true
    case "MENU_BTN_CREATE":        return .MENU_BTN_CREATE, true
    case "MENU_BTN_CANCEL":        return .MENU_BTN_CANCEL, true
    case "MENU_BTN_PLAY":          return .MENU_BTN_PLAY, true
    case "MENU_BTN_CONFIRM":       return .MENU_BTN_CONFIRM, true
    case "MENU_BTN_DELETE":        return .MENU_BTN_DELETE, true
    case "MENU_BTN_SINGLEPLAYER":  return .MENU_BTN_SINGLEPLAYER, true
    case "MENU_BTN_HOST":          return .MENU_BTN_HOST, true
    case "MENU_BTN_JOIN":          return .MENU_BTN_JOIN, true
    case "MENU_HOST_IP_LABEL":     return .MENU_HOST_IP_LABEL, true
    case "MENU_BTN_CONNECT":       return .MENU_BTN_CONNECT, true
    case "MENU_BTN_BACK":          return .MENU_BTN_BACK, true
    case "MENU_WAITING":           return .MENU_WAITING, true
    case "MENU_CONNECTING":        return .MENU_CONNECTING, true
    case "MENU_ESC_CANCEL":        return .MENU_ESC_CANCEL, true
    case "MENU_CHAR_DEFAULT":      return .MENU_CHAR_DEFAULT, true
    case "MENU_BTN_SETTINGS":     return .MENU_BTN_SETTINGS, true
    case "MENU_BTN_EXIT":         return .MENU_BTN_EXIT, true

    case "HUD_EXTRACT":            return .HUD_EXTRACT, true
    case "HUD_LOOT_FILTER":        return .HUD_LOOT_FILTER, true
    case "HUD_FILTER_ALL":         return .HUD_FILTER_ALL, true
    case "HUD_FILTER_RARE":        return .HUD_FILTER_RARE, true
    case "HUD_FILTER_EPIC":        return .HUD_FILTER_EPIC, true
    case "HUD_FILTER_LEGENDARY":   return .HUD_FILTER_LEGENDARY, true
    case "HUD_FILTER_UNIQUE":      return .HUD_FILTER_UNIQUE, true
    case "HUD_RAID_TIMER":         return .HUD_RAID_TIMER, true
    case "HUD_WARNING":            return .HUD_WARNING, true
    case "HUD_BOSS_APPROACHES":    return .HUD_BOSS_APPROACHES, true
    case "HUD_ITEM_ACTIVE":        return .HUD_ITEM_ACTIVE, true
    case "HUD_ITEM_PASSIVE":       return .HUD_ITEM_PASSIVE, true
    case "HUD_LEVELUP":            return .HUD_LEVELUP, true
    case "HUD_STATPOINT":          return .HUD_STATPOINT, true

    case "PAUSE_TITLE":            return .PAUSE_TITLE, true
    case "PAUSE_BTN_RESUME":       return .PAUSE_BTN_RESUME, true
    case "PAUSE_BTN_KEYBINDS":     return .PAUSE_BTN_KEYBINDS, true
    case "PAUSE_BTN_QUIT":         return .PAUSE_BTN_QUIT, true

    case "SETTINGS_TITLE":         return .SETTINGS_TITLE, true
    case "SETTINGS_RESOLUTION":    return .SETTINGS_RESOLUTION, true
    case "SETTINGS_WINDOW_MODE":   return .SETTINGS_WINDOW_MODE, true
    case "SETTINGS_BORDERLESS":    return .SETTINGS_BORDERLESS, true
    case "SETTINGS_WINDOWED":      return .SETTINGS_WINDOWED, true
    case "SETTINGS_VOLUME":        return .SETTINGS_VOLUME, true
    case "SETTINGS_SFX":           return .SETTINGS_SFX, true
    case "SETTINGS_MUSIC":         return .SETTINGS_MUSIC, true
    case "SETTINGS_AMBIENCE":      return .SETTINGS_AMBIENCE, true
    case "SETTINGS_VOICE":         return .SETTINGS_VOICE, true
    case "SETTINGS_LANGUAGE":       return .SETTINGS_LANGUAGE, true
    case "SETTINGS_BTN_KEYBINDS":  return .SETTINGS_BTN_KEYBINDS, true
    case "SETTINGS_BTN_CLOSE":     return .SETTINGS_BTN_CLOSE, true
    case "SETTINGS_BTN_EXIT":      return .SETTINGS_BTN_EXIT, true

    case "LANG_EN":                return .LANG_EN, true
    case "LANG_ES":                return .LANG_ES, true
    case "LANG_PT":                return .LANG_PT, true

    case "KEYBINDS_TITLE":              return .KEYBINDS_TITLE, true
    case "KEYBINDS_SECTION_GAMEPLAY":   return .KEYBINDS_SECTION_GAMEPLAY, true
    case "KEYBINDS_SECTION_UI":         return .KEYBINDS_SECTION_UI, true
    case "KEYBINDS_PRESS_KEY":          return .KEYBINDS_PRESS_KEY, true
    case "KEYBINDS_BTN_RESET":          return .KEYBINDS_BTN_RESET, true
    case "KEYBINDS_BTN_CLOSE":          return .KEYBINDS_BTN_CLOSE, true
    case "KEYBINDS_ESC_CANCEL":         return .KEYBINDS_ESC_CANCEL, true

    case "INV_TITLE":              return .INV_TITLE, true
    case "INV_ARMOR":              return .INV_ARMOR, true
    case "INV_SLOT_HEAD":          return .INV_SLOT_HEAD, true
    case "INV_SLOT_CHEST":         return .INV_SLOT_CHEST, true
    case "INV_SLOT_BOOTS":         return .INV_SLOT_BOOTS, true
    case "INV_WEAPONS":            return .INV_WEAPONS, true
    case "INV_SLOT_WEAPON":        return .INV_SLOT_WEAPON, true
    case "INV_SLOT_OFFHAND":       return .INV_SLOT_OFFHAND, true
    case "INV_ABILITIES":          return .INV_ABILITIES, true
    case "INV_BACKPACK":           return .INV_BACKPACK, true
    case "INV_BTN_CLOSE":          return .INV_BTN_CLOSE, true
    case "INV_UNEQUIPPED":         return .INV_UNEQUIPPED, true

    case "STATS_TITLE":            return .STATS_TITLE, true
    case "STATS_STRENGTH":         return .STATS_STRENGTH, true
    case "STATS_DEXTERITY":        return .STATS_DEXTERITY, true
    case "STATS_SCIENCE":          return .STATS_SCIENCE, true
    case "STATS_HP_BONUS":         return .STATS_HP_BONUS, true
    case "STATS_SPEED_BONUS":      return .STATS_SPEED_BONUS, true
    case "STATS_ENERGY_BONUS":     return .STATS_ENERGY_BONUS, true
    case "STATS_SECTION":          return .STATS_SECTION, true
    case "STATS_HISTORY":          return .STATS_HISTORY, true
    case "STATS_RAIDS":            return .STATS_RAIDS, true
    case "STATS_KILLS":            return .STATS_KILLS, true
    case "STATS_DEATHS":           return .STATS_DEATHS, true
    case "STATS_BEST_EXTRACT":     return .STATS_BEST_EXTRACT, true
    case "STATS_BTN_CLOSE":        return .STATS_BTN_CLOSE, true

    case "MUT_INTERACT":           return .MUT_INTERACT, true
    case "MUT_BRANCH_CORPUS":      return .MUT_BRANCH_CORPUS, true
    case "MUT_BRANCH_SHADOW":      return .MUT_BRANCH_SHADOW, true
    case "MUT_BRANCH_VENOM":       return .MUT_BRANCH_VENOM, true
    case "MUT_TITLE":              return .MUT_TITLE, true
    case "MUT_SERUMS":             return .MUT_SERUMS, true
    case "MUT_COST":               return .MUT_COST, true
    case "MUT_ACQUIRED":           return .MUT_ACQUIRED, true
    case "MUT_CONFLICT":           return .MUT_CONFLICT, true
    case "MUT_CRAFT_HINT":         return .MUT_CRAFT_HINT, true
    case "MUT_FOOTER":             return .MUT_FOOTER, true
    case "MUT_RESET":              return .MUT_RESET, true

    case "HUB_INTERACT":           return .HUB_INTERACT, true
    case "HUB_LABEL":              return .HUB_LABEL, true
    case "HUB_STASH":              return .HUB_STASH, true
    case "HUB_LEVEL_SELECT":       return .HUB_LEVEL_SELECT, true
    case "HUB_LEVEL_N":            return .HUB_LEVEL_N, true
    case "HUB_NO_LEVELS":          return .HUB_NO_LEVELS, true
    case "HUB_ESC_CANCEL":         return .HUB_ESC_CANCEL, true
    case "HUB_BTN_RETURN":         return .HUB_BTN_RETURN, true
    case "HUB_BTN_RETRY":          return .HUB_BTN_RETRY, true

    case "EXTRACT_TITLE":          return .EXTRACT_TITLE, true
    case "EXTRACT_SUBTITLE":       return .EXTRACT_SUBTITLE, true
    case "EXTRACT_GOLD":           return .EXTRACT_GOLD, true
    case "EXTRACT_SERUMS":         return .EXTRACT_SERUMS, true
    case "EXTRACT_STASH_TOTAL":    return .EXTRACT_STASH_TOTAL, true

    case "DEATH_TITLE":            return .DEATH_TITLE, true
    case "DEATH_MSG":              return .DEATH_MSG, true
    case "DEATH_STASH":            return .DEATH_STASH, true

    case "SHOP_INTERACT":          return .SHOP_INTERACT, true
    case "SHOP_TITLE":             return .SHOP_TITLE, true
    case "SHOP_GOLD":              return .SHOP_GOLD, true
    case "SHOP_SOLD_OUT":          return .SHOP_SOLD_OUT, true
    case "SHOP_SELL":              return .SHOP_SELL, true
    case "SHOP_ESC_CLOSE":         return .SHOP_ESC_CLOSE, true

    case "ABILITY_VENDOR_INTERACT": return .ABILITY_VENDOR_INTERACT, true
    case "ABILITY_VENDOR_SUBTITLE": return .ABILITY_VENDOR_SUBTITLE, true

    case "STASH_INTERACT":         return .STASH_INTERACT, true
    case "STASH_TITLE":            return .STASH_TITLE, true
    case "STASH_DEPOSIT_ALL":      return .STASH_DEPOSIT_ALL, true

    case "ITEM_CORRUPTED_RELIQUARY_NAME":  return .ITEM_CORRUPTED_RELIQUARY_NAME, true
    case "ITEM_CORRUPTED_RELIQUARY_DESC":  return .ITEM_CORRUPTED_RELIQUARY_DESC, true
    case "ITEM_LEATHER_CARAPACE_NAME":     return .ITEM_LEATHER_CARAPACE_NAME, true
    case "ITEM_LEATHER_CARAPACE_DESC":     return .ITEM_LEATHER_CARAPACE_DESC, true
    case "ITEM_IRON_BULWARK_NAME":         return .ITEM_IRON_BULWARK_NAME, true
    case "ITEM_IRON_BULWARK_DESC":         return .ITEM_IRON_BULWARK_DESC, true
    case "ITEM_BANDOLIER_RIG_NAME":        return .ITEM_BANDOLIER_RIG_NAME, true
    case "ITEM_BANDOLIER_RIG_DESC":        return .ITEM_BANDOLIER_RIG_DESC, true
    case "ITEM_ETHEREAL_SHARD_NAME":       return .ITEM_ETHEREAL_SHARD_NAME, true
    case "ITEM_ETHEREAL_SHARD_DESC":       return .ITEM_ETHEREAL_SHARD_DESC, true
    case "ITEM_COYOTE_STRIDERS_NAME":      return .ITEM_COYOTE_STRIDERS_NAME, true
    case "ITEM_COYOTE_STRIDERS_DESC":      return .ITEM_COYOTE_STRIDERS_DESC, true
    case "ITEM_BONE_FETISH_NAME":          return .ITEM_BONE_FETISH_NAME, true
    case "ITEM_BONE_FETISH_DESC":          return .ITEM_BONE_FETISH_DESC, true
    case "ITEM_HAMMERLOCK_PISTOL_NAME":    return .ITEM_HAMMERLOCK_PISTOL_NAME, true
    case "ITEM_HAMMERLOCK_PISTOL_DESC":    return .ITEM_HAMMERLOCK_PISTOL_DESC, true
    case "ITEM_LIGHTCOIL_REPEATER_NAME":   return .ITEM_LIGHTCOIL_REPEATER_NAME, true
    case "ITEM_LIGHTCOIL_REPEATER_DESC":   return .ITEM_LIGHTCOIL_REPEATER_DESC, true
    case "ITEM_DRUMFEED_CARBINE_NAME":     return .ITEM_DRUMFEED_CARBINE_NAME, true
    case "ITEM_DRUMFEED_CARBINE_DESC":     return .ITEM_DRUMFEED_CARBINE_DESC, true
    case "ITEM_DESERT_MACHETE_NAME":       return .ITEM_DESERT_MACHETE_NAME, true
    case "ITEM_DESERT_MACHETE_DESC":       return .ITEM_DESERT_MACHETE_DESC, true
    case "ITEM_WAR_CLEAVER_NAME":          return .ITEM_WAR_CLEAVER_NAME, true
    case "ITEM_WAR_CLEAVER_DESC":          return .ITEM_WAR_CLEAVER_DESC, true
    case "ITEM_QUICKFANG_KNIFE_NAME":      return .ITEM_QUICKFANG_KNIFE_NAME, true
    case "ITEM_QUICKFANG_KNIFE_DESC":      return .ITEM_QUICKFANG_KNIFE_DESC, true
    case "ITEM_NECROTIC_SERUM_NAME":       return .ITEM_NECROTIC_SERUM_NAME, true
    case "ITEM_NECROTIC_SERUM_DESC":       return .ITEM_NECROTIC_SERUM_DESC, true
    case "ITEM_NECROTIC_SERUM3_NAME":      return .ITEM_NECROTIC_SERUM3_NAME, true
    case "ITEM_NECROTIC_SERUM3_DESC":      return .ITEM_NECROTIC_SERUM3_DESC, true

    case "INTERACT_OPEN":              return .INTERACT_OPEN, true
    case "INTERACT_UNLOCK":            return .INTERACT_UNLOCK, true
    case "INTERACT_OPENS_ELSEWHERE":   return .INTERACT_OPENS_ELSEWHERE, true
    case "INTERACT_PULL_LEVER":        return .INTERACT_PULL_LEVER, true
    case "INTERACT_OPEN_CHEST":        return .INTERACT_OPEN_CHEST, true
    case "INTERACT_BREAK_CRATE":       return .INTERACT_BREAK_CRATE, true
    case "INTERACT_OPEN_LOCKER":       return .INTERACT_OPEN_LOCKER, true
    case "INTERACT_SEARCH_CABINET":    return .INTERACT_SEARCH_CABINET, true
    case "INTERACT_READ_DOCUMENT":     return .INTERACT_READ_DOCUMENT, true
    case "INTERACT_WIND_PHONOGRAPH":   return .INTERACT_WIND_PHONOGRAPH, true
    case "INTERACT_TAKE_KEY":          return .INTERACT_TAKE_KEY, true

    case "LORE_01_TITLE":             return .LORE_01_TITLE, true
    case "LORE_01_BODY":              return .LORE_01_BODY, true
    case "LORE_02_TITLE":             return .LORE_02_TITLE, true
    case "LORE_02_BODY":              return .LORE_02_BODY, true
    case "LORE_03_TITLE":             return .LORE_03_TITLE, true
    case "LORE_03_BODY":              return .LORE_03_BODY, true

    case "REC_01_TITLE":              return .REC_01_TITLE, true
    case "REC_01_TRANSCRIPT":         return .REC_01_TRANSCRIPT, true
    case "REC_02_TITLE":              return .REC_02_TITLE, true
    case "REC_02_TRANSCRIPT":         return .REC_02_TRANSCRIPT, true
    case "REC_03_TITLE":              return .REC_03_TITLE, true
    case "REC_03_TRANSCRIPT":         return .REC_03_TRANSCRIPT, true

    case "CLASS_SELECT_TITLE":        return .CLASS_SELECT_TITLE, true
    case "CLASS_SELECT_BEGIN":        return .CLASS_SELECT_BEGIN, true
    case "CLASS_STARTER_ABILITY":     return .CLASS_STARTER_ABILITY, true
    case "CLASS_STARTER_WEAPON":      return .CLASS_STARTER_WEAPON, true
    case "CLASS_STAT_STR":            return .CLASS_STAT_STR, true
    case "CLASS_STAT_DEX":            return .CLASS_STAT_DEX, true
    case "CLASS_STAT_SCI":            return .CLASS_STAT_SCI, true

    case "CLASS_NURSE_NAME":          return .CLASS_NURSE_NAME, true
    case "CLASS_PR1S_NAME":           return .CLASS_PR1S_NAME, true
    case "CLASS_SHERIFF_NAME":        return .CLASS_SHERIFF_NAME, true
    case "CLASS_SRBRAIN_NAME":        return .CLASS_SRBRAIN_NAME, true

    case "CLASS_NURSE_TITLE":         return .CLASS_NURSE_TITLE, true
    case "CLASS_PR1S_TITLE":          return .CLASS_PR1S_TITLE, true
    case "CLASS_SHERIFF_TITLE":       return .CLASS_SHERIFF_TITLE, true
    case "CLASS_SRBRAIN_TITLE":       return .CLASS_SRBRAIN_TITLE, true

    case "CLASS_NURSE_DESC":          return .CLASS_NURSE_DESC, true
    case "CLASS_PR1S_DESC":           return .CLASS_PR1S_DESC, true
    case "CLASS_SHERIFF_DESC":        return .CLASS_SHERIFF_DESC, true
    case "CLASS_SRBRAIN_DESC":        return .CLASS_SRBRAIN_DESC, true

    case "CLASS_NURSE_WEAPON":        return .CLASS_NURSE_WEAPON, true
    case "CLASS_PR1S_WEAPON":         return .CLASS_PR1S_WEAPON, true
    case "CLASS_SHERIFF_WEAPON":      return .CLASS_SHERIFF_WEAPON, true
    case "CLASS_SRBRAIN_WEAPON":      return .CLASS_SRBRAIN_WEAPON, true

    case "QUEST_BOARD_NPC_NAME":           return .QUEST_BOARD_NPC_NAME, true
    case "QUEST_BOARD_TITLE":              return .QUEST_BOARD_TITLE, true
    case "QUEST_BOARD_INTERACT":           return .QUEST_BOARD_INTERACT, true
    case "QUEST_SURVIVORS_MARK_TITLE":     return .QUEST_SURVIVORS_MARK_TITLE, true
    case "QUEST_SURVIVORS_MARK_LORE":      return .QUEST_SURVIVORS_MARK_LORE, true
    case "QUEST_SURVIVORS_MARK_OBJ":       return .QUEST_SURVIVORS_MARK_OBJ, true
    case "QUEST_THE_HORDE_TITLE":          return .QUEST_THE_HORDE_TITLE, true
    case "QUEST_THE_HORDE_LORE":           return .QUEST_THE_HORDE_LORE, true
    case "QUEST_THE_HORDE_OBJ":            return .QUEST_THE_HORDE_OBJ, true
    case "QUEST_ABERRATION_TITLE":         return .QUEST_ABERRATION_TITLE, true
    case "QUEST_ABERRATION_LORE":          return .QUEST_ABERRATION_LORE, true
    case "QUEST_ABERRATION_OBJ":           return .QUEST_ABERRATION_OBJ, true
    case "QUEST_BLOODLINES_TITLE":         return .QUEST_BLOODLINES_TITLE, true
    case "QUEST_BLOODLINES_LORE":          return .QUEST_BLOODLINES_LORE, true
    case "QUEST_BLOODLINES_OBJ":           return .QUEST_BLOODLINES_OBJ, true
    case "QUEST_THE_DEEP_RUN_TITLE":       return .QUEST_THE_DEEP_RUN_TITLE, true
    case "QUEST_THE_DEEP_RUN_LORE":        return .QUEST_THE_DEEP_RUN_LORE, true
    case "QUEST_THE_DEEP_RUN_OBJ":         return .QUEST_THE_DEEP_RUN_OBJ, true
    case "QUEST_ELITE_PREDATOR_TITLE":     return .QUEST_ELITE_PREDATOR_TITLE, true
    case "QUEST_ELITE_PREDATOR_LORE":      return .QUEST_ELITE_PREDATOR_LORE, true
    case "QUEST_ELITE_PREDATOR_OBJ":       return .QUEST_ELITE_PREDATOR_OBJ, true
    case "QUEST_PERFECT_RUN_TITLE":        return .QUEST_PERFECT_RUN_TITLE, true
    case "QUEST_PERFECT_RUN_LORE":         return .QUEST_PERFECT_RUN_LORE, true
    case "QUEST_PERFECT_RUN_OBJ":          return .QUEST_PERFECT_RUN_OBJ, true
    case "QUEST_FINAL_FORM_TITLE":         return .QUEST_FINAL_FORM_TITLE, true
    case "QUEST_FINAL_FORM_LORE":          return .QUEST_FINAL_FORM_LORE, true
    case "QUEST_FINAL_FORM_OBJ":           return .QUEST_FINAL_FORM_OBJ, true
    }
    return {}, false
}


loc_lookup :: proc(raw: cstring) -> cstring {
    if raw == nil || len(raw) == 0 { return raw }
    key, found := _loc_key_from_name(string(raw))
    if !found { return raw }
    return t(key)
}
