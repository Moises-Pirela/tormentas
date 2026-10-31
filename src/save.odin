package main

import "core:os"
import "core:mem"

SAVE_PATH        :: "save/player.bin"
CHAR_SAVE_PATH   :: "save/characters.bin"
SAVE_MAGIC       :: u32(0x544F524D)
SAVE_VERSION     :: u16(7)
SAVE_MAX_ITEMS   :: 64
CHAR_SAVE_MAGIC  :: u32(0x544F524E)
CHAR_SAVE_VER    :: u16(2)
MAX_CHAR_SLOTS   :: 5

PlayerLifetimeStats :: struct #packed {
    successful_raids: i32,
    enemies_killed:   i32,
    deaths:           i32,
    max_extract_gold: i32,
    bosses_killed:    i32,
    elites_killed:    i32,
    deep_extracts:    i32,
    _reserved:        [9]i32,
}

g_lifetime_stats: PlayerLifetimeStats

SavedAffix :: struct #packed {
    affix_type: u8,
    _pad:       [3]u8,
    value:      f32,
}

SavedItem :: struct #packed {
    is_equipped:        u8,
    equip_slot_idx:     u8,
    pack_x:             i16,
    pack_y:             i16,
    _pad:               u16,

    slot:               u8,
    rarity:             u8,
    mutation_type:      u8,
    ability_type:       u8,
    ability_level:      u8,
    _ability_pad:       [2]u8,
    serum_value:        i32,
    grid_w:             u8,
    grid_h:             u8,
    req_str:            u8,
    req_dex:            u8,
    req_sci:            u8,
    affix_count:        u8,
    flags:              u8,
    weapon_archetype:   u8,
    melee_damage:       f32,
    melee_range:        f32,
    melee_spread:       f32,
    melee_cooldown_max: f32,
    base_damage:        f32,
    base_fire_rate:     f32,
    base_ammo_max:      u8,
    _base_ammo_pad:     [3]u8,
    base_reload_time:   f32,
    base_proj_speed:    f32,
    base_armor:         f32,
    base_shield:        f32,
    affixes:            [MAX_AFFIXES]SavedAffix,

    name_len: u8,
    name:     [RENDER_NAME_CAP]u8,
    icon_len: u8,
    icon:     [RENDER_ICON_CAP]u8,
    desc_len: u8,
    desc:     [RENDER_DESC_CAP]u8,
}

PlayerSaveFile :: struct #packed {
    magic:          u32,
    version:        u16,
    character:      u16,

    level:          i32,
    xp:             f32,
    xp_next:        f32,
    stat_points:    i32,
    strength:       i32,
    dexterity:      i32,
    science:        i32,
    base_hp:        f32,
    base_energy:    f32,
    base_speed:     f32,
    current_hp:     f32,
    current_energy: f32,
    current_shield: f32,
    wallet_gold:    i32,

    stash_gold:     i32,
    stash_serums:   i32,
    stash_item_count: u16,
    _stash_pad:       u16,
    stash_items:      [STASH_MAX_ITEMS]SavedItem,

    item_count:     u16,
    _pad2:          u16,

    lifetime:       PlayerLifetimeStats,

    mut_serums:     i32,
    mut_count:      u8,
    _mut_pad:       [3]u8,
    mut_types:      [MAX_MUTATION_SLOTS]u8,
    _mut_align:     u8,

    items:          [SAVE_MAX_ITEMS]SavedItem,

    quest_completed: u8,
    _quest_pad:      [3]u8,
}

PlayerSaveFileV4 :: struct #packed {
    magic:          u32,
    version:        u16,
    _pad:           u16,

    level:          i32,
    xp:             f32,
    xp_next:        f32,
    stat_points:    i32,
    strength:       i32,
    dexterity:      i32,
    science:        i32,
    base_hp:        f32,
    base_energy:    f32,
    base_speed:     f32,
    current_hp:     f32,
    current_energy: f32,
    current_shield: f32,
    wallet_gold:    i32,

    stash_gold:     i32,
    stash_serums:   i32,

    item_count:     u16,
    _pad2:          u16,

    lifetime:       PlayerLifetimeStats,

    mut_serums:     i32,
    mut_count:      u8,
    _mut_pad:       [3]u8,
    mut_types:      [MAX_MUTATION_SLOTS]u8,
    _mut_align:     u8,

    items:          [SAVE_MAX_ITEMS]SavedItem,
}

CharSlot :: struct #packed {
    exists:     u8,
    _pad:       [7]u8,
    name:       [PLAYER_NAME_MAX + 1]u8,
    _npad:      [6]u8,
    level:      i32,
    deaths:     i32,
    raids_done: i32,
    _reserved:  [32]u8,
    player:     PlayerSaveFile,
}

CharSaveFile :: struct #packed {
    magic:   u32,
    version: u16,
    _pad:    u16,
    slots:   [MAX_CHAR_SLOTS]CharSlot,
}

CharSlotV1 :: struct #packed {
    exists:     u8,
    _pad:       [7]u8,
    name:       [PLAYER_NAME_MAX + 1]u8,
    _npad:      [6]u8,
    level:      i32,
    deaths:     i32,
    raids_done: i32,
    _reserved:  [32]u8,
    player:     PlayerSaveFileV4,
}

CharSaveFileV1 :: struct #packed {
    magic:   u32,
    version: u16,
    _pad:    u16,
    slots:   [MAX_CHAR_SLOTS]CharSlotV1,
}

g_active_slot: int = -1
g_char_save:   CharSaveFile

chars_load_all :: proc() {
    raw, ok := read_game_file(CHAR_SAVE_PATH)
    if ok {
        defer delete(raw)
        if len(raw) >= size_of(CharSaveFile) {
            csf := (^CharSaveFile)(raw_data(raw))^
            if csf.magic == CHAR_SAVE_MAGIC && csf.version == CHAR_SAVE_VER {
                g_char_save = csf
                return
            }
        }
        if len(raw) >= size_of(CharSaveFileV1) {
            old := (^CharSaveFileV1)(raw_data(raw))^
            if old.magic == CHAR_SAVE_MAGIC && old.version == 1 {
                g_char_save = {}
                g_char_save.magic   = CHAR_SAVE_MAGIC
                g_char_save.version = CHAR_SAVE_VER
                for i in 0..<MAX_CHAR_SLOTS {
                    if old.slots[i].exists == 0 { continue }
                    g_char_save.slots[i].exists = 1
                    copy(g_char_save.slots[i].name[:], old.slots[i].name[:])
                    g_char_save.slots[i].level      = old.slots[i].level
                    g_char_save.slots[i].deaths     = old.slots[i].deaths
                    g_char_save.slots[i].raids_done = old.slots[i].raids_done
                    g_char_save.slots[i].player     = _migrate_player_v4(&old.slots[i].player)
                }
                chars_save_all()
                return
            }
        }
    }

    g_char_save = {}
    g_char_save.magic   = CHAR_SAVE_MAGIC
    g_char_save.version = CHAR_SAVE_VER

    legacy, lok := read_game_file(SAVE_PATH)
    if lok {
        defer delete(legacy)
        if len(legacy) >= size_of(PlayerSaveFile) {
            psf := (^PlayerSaveFile)(raw_data(legacy))^
            if psf.magic == SAVE_MAGIC && psf.version == SAVE_VERSION {
                g_char_save.slots[0].exists = 1
                copy(g_char_save.slots[0].name[:], "Wanderer")
                g_char_save.slots[0].level      = psf.level
                g_char_save.slots[0].deaths     = psf.lifetime.deaths
                g_char_save.slots[0].raids_done = psf.lifetime.successful_raids
                g_char_save.slots[0].player     = psf
            }
        } else if len(legacy) >= size_of(PlayerSaveFileV4) {
            psf4 := (^PlayerSaveFileV4)(raw_data(legacy))^
            if psf4.magic == SAVE_MAGIC && psf4.version == 4 {
                g_char_save.slots[0].exists = 1
                copy(g_char_save.slots[0].name[:], "Wanderer")
                g_char_save.slots[0].level      = psf4.level
                g_char_save.slots[0].deaths     = psf4.lifetime.deaths
                g_char_save.slots[0].raids_done = psf4.lifetime.successful_raids
                g_char_save.slots[0].player     = _migrate_player_v4(&psf4)
            }
        }
    }

    chars_save_all()
}

chars_save_all :: proc() {
    os.make_directory("save")
    data := (^[size_of(CharSaveFile)]u8)(&g_char_save)^
    write_game_file(CHAR_SAVE_PATH, data[:])
}

char_slot_create :: proc(idx: int, name: []u8, save_to_disk: bool = true) {
    if idx < 0 || idx >= MAX_CHAR_SLOTS { return }
    s := &g_char_save.slots[idx]
    mem.zero(s, size_of(CharSlot))
    s.exists = 1
    n := min(len(name), PLAYER_NAME_MAX)
    copy(s.name[:], name[:n])
    if save_to_disk { chars_save_all() }
}

char_slot_delete :: proc(idx: int) {
    if idx < 0 || idx >= MAX_CHAR_SLOTS { return }
    mem.zero(&g_char_save.slots[idx], size_of(CharSlot))
    if g_active_slot == idx { g_active_slot = -1 }
    chars_save_all()
}

@(private = "file")
_migrate_player_v4 :: proc(old: ^PlayerSaveFileV4) -> PlayerSaveFile {
    save: PlayerSaveFile
    save.magic          = SAVE_MAGIC
    save.version        = SAVE_VERSION
    save.level          = old.level
    save.xp             = old.xp
    save.xp_next        = old.xp_next
    save.stat_points    = old.stat_points
    save.strength       = old.strength
    save.dexterity      = old.dexterity
    save.science        = old.science
    save.base_hp        = old.base_hp
    save.base_energy    = old.base_energy
    save.base_speed     = old.base_speed
    save.current_hp     = old.current_hp
    save.current_energy = old.current_energy
    save.current_shield = old.current_shield
    save.wallet_gold    = old.wallet_gold
    save.stash_gold     = old.stash_gold
    save.stash_serums   = old.stash_serums
    save.item_count     = old.item_count
    save.lifetime       = old.lifetime
    save.mut_serums     = old.mut_serums
    save.mut_count      = old.mut_count
    copy(save.mut_types[:], old.mut_types[:])
    copy(save.items[:], old.items[:])
    return save
}

class_idx_for_slot :: proc(slot_idx: int) -> int {
    if slot_idx >= 0 && slot_idx < MAX_CHAR_SLOTS {
        b := g_char_save.slots[slot_idx]._reserved[0]
        if b > 0 { return int(b) - 1 }
    }
    return g_selected_class_idx
}

strip_player_carried :: proc(w: ^World, pid: int) {
    if !world_is_valid(w, pid)                  { return }
    if !world_has_component(w, pid, .Inventory) { return }

    inv := comp_get(w, pid, .Inventory, InventoryComp)

    for slot_idx in 0..<EQUIP_SLOT_COUNT {
        slot := EquipSlot(slot_idx)
        eid  := inv.equipped[slot_idx]

        if (slot == .Flask1 || slot == .Flask2) &&
            world_is_valid(w, eid) &&
            world_has_component(w, eid, .Item) &&
            comp_get(w, eid, .Item, ItemComp).rarity == .Normal &&
            world_has_component(w, eid, .Flask) {
            fc         := comp_get(w, eid, .Flask, FlaskComp)
            fc.charges  = fc.max_charges
            continue
        }

        inv.equipped[slot_idx] = INVALID_ENTITY
    }

    for &cell in inv.backpack { cell = INVALID_ENTITY }

    if world_has_component(w, pid, .Wallet) {
        comp_get(w, pid, .Wallet, WalletComp).gold = 0
    }
}

compute_extract_value :: proc(w: ^World, pid: int) -> int {
    total := 0
    if world_has_component(w, pid, .Wallet) {
        total += comp_get(w, pid, .Wallet, WalletComp).gold
    }
    if !world_has_component(w, pid, .Inventory) { return total }
    inv  := comp_get(w, pid, .Inventory, InventoryComp)
    seen: map[int]bool
    defer delete(seen)
    for eid in inv.equipped {
        if eid == INVALID_ENTITY               { continue }
        if seen[eid]                              { continue }
        seen[eid] = true
        if !world_has_component(w, eid, .Item) { continue }
        total += item_gold_value(comp_get(w, eid, .Item, ItemComp))
    }
    for cell in inv.backpack {
        if cell == INVALID_ENTITY               { continue }
        if seen[cell]                              { continue }
        seen[cell] = true
        if !world_has_component(w, cell, .Item) { continue }
        item := comp_get(w, cell, .Item, ItemComp)
        if item.serum_value > 0                    { continue }
        total += item_gold_value(item)
    }
    return total
}

@(private = "file")
_build_player_save :: proc(w: ^World, pid: int) -> PlayerSaveFile {
    save: PlayerSaveFile
    save.magic      = SAVE_MAGIC
    save.version    = SAVE_VERSION
    save.lifetime   = g_lifetime_stats

    char_idx := 0
    stems_sv := PLAYER_STEMS
    for i in 0..<len(stems_sv) {
        if stems_sv[i] == g_player_stem { char_idx = i; break }
    }
    save.character = u16(char_idx)

    save.quest_completed = g_quest_completed[g_session.local_slot]

    if world_has_component(w, pid, .Stats) {
        st              := comp_get(w, pid, .Stats, StatsComp)
        save.level       = i32(st.level)
        save.xp          = st.xp
        save.xp_next     = st.xp_next
        save.stat_points = i32(st.stat_points)
        save.strength    = i32(st.strength)
        save.dexterity   = i32(st.dexterity)
        save.science     = i32(st.science)
        save.base_hp     = st.base_hp
        save.base_energy = st.base_energy
        save.base_speed  = st.base_speed
    }

    if world_has_component(w, pid, .Health) {
        h                   := comp_get(w, pid, .Health, HealthComp)
        save.current_hp      = h.current
        save.current_energy  = h.energy
        save.current_shield  = h.shield
    }

    if world_has_component(w, pid, .Wallet) {
        save.wallet_gold = i32(comp_get(w, pid, .Wallet, WalletComp).gold)
    }

    st := local_stash()
    save.stash_gold   = i32(st.gold)
    save.stash_serums = i32(st.serums)
    for i in 0..<st.item_count {
        eid := st.item_ids[i]
        if !world_is_valid(w, eid)             { continue }
        if !world_has_component(w, eid, .Item) { continue }
        if save.stash_item_count >= STASH_MAX_ITEMS { break }

        rec := &save.stash_items[save.stash_item_count]
        save.stash_item_count += 1
        rec.is_equipped = 0
        item := comp_get(w, eid, .Item, ItemComp)
        rec.pack_x      = i16(item.pack_x)
        rec.pack_y      = i16(item.pack_y)
        _save_fill_item(rec, item)
        if world_has_component(w, eid, .RenderConfig) {
            _save_fill_render(rec, comp_get(w, eid, .RenderConfig, RenderConfigComp))
        }
    }

    if world_has_component(w, pid, .MutationContainer) {
        mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
        save.mut_serums = i32(mc.serums)
        save.mut_count  = u8(mc.entity_count)
        for i in 0..<mc.entity_count {
            eid := mc.entities[i]
            if !world_is_valid(w, eid)              { continue }
            if !world_has_component(w, eid, .Mut)   { continue }
            save.mut_types[i] = u8(comp_get(w, eid, .Mut, MutComp).type_id)
        }
    }

    if world_has_component(w, pid, .Inventory) {
        inv := comp_get(w, pid, .Inventory, InventoryComp)

        for slot_idx in 0..<EQUIP_SLOT_COUNT {
            eid := inv.equipped[slot_idx]
            if !world_is_valid(w, eid)             { continue }
            if !world_has_component(w, eid, .Item) { continue }
            if save.item_count >= SAVE_MAX_ITEMS       { break }

            rec := &save.items[save.item_count]
            save.item_count += 1
            rec.is_equipped    = 1
            rec.equip_slot_idx = u8(slot_idx)
            _save_fill_item(rec, comp_get(w, eid, .Item, ItemComp))
            if world_has_component(w, eid, .RenderConfig) {
                _save_fill_render(rec, comp_get(w, eid, .RenderConfig, RenderConfigComp))
            }
            if world_has_component(w, eid, .Flask) {
                _save_fill_flask(rec, comp_get(w, eid, .Flask, FlaskComp))
            }
        }

        seen: map[int]bool
        defer delete(seen)
        for cell in inv.backpack {
            if cell == INVALID_ENTITY                { continue }
            if seen[cell]                               { continue }
            seen[cell] = true
            if !world_has_component(w, cell, .Item) { continue }
            if save.item_count >= SAVE_MAX_ITEMS        { break }

            rec  := &save.items[save.item_count]
            save.item_count += 1
            item := comp_get(w, cell, .Item, ItemComp)
            rec.is_equipped = 0
            rec.pack_x      = i16(item.pack_x)
            rec.pack_y      = i16(item.pack_y)
            _save_fill_item(rec, item)
            if world_has_component(w, cell, .RenderConfig) {
                _save_fill_render(rec, comp_get(w, cell, .RenderConfig, RenderConfigComp))
            }
            if world_has_component(w, cell, .Flask) {
                _save_fill_flask(rec, comp_get(w, cell, .Flask, FlaskComp))
            }
        }
    }

    return save
}

save_player :: proc(w: ^World, pid: int) {
    if g_active_slot < 0 || g_active_slot >= MAX_CHAR_SLOTS { return }
    save := _build_player_save(w, pid)
    s := &g_char_save.slots[g_active_slot]
    s.player     = save
    s.level      = save.level
    s.deaths     = save.lifetime.deaths
    s.raids_done = save.lifetime.successful_raids
    chars_save_all()
}

player_to_bytes :: proc(w: ^World, pid: int) -> []u8 {
    save := _build_player_save(w, pid)
    n    := size_of(PlayerSaveFile)
    out  := make([]u8, n, context.temp_allocator)
    mem.copy(raw_data(out), &save, n)
    return out
}

@(private = "file")
_apply_player_save :: proc(w: ^World, pid: int, save: ^PlayerSaveFile) {
    if slot := player_slot_for_id(w, pid); slot >= 0 {
        stems    := PLAYER_STEMS
        char_idx := int(save.character)
        if char_idx < 0 || char_idx >= len(stems) { char_idx = 0 }
        g_player_stems[slot] = stems[char_idx]
    }

    if world_has_component(w, pid, .Stats) {
        st             := comp_get(w, pid, .Stats, StatsComp)
        st.level        = int(save.level)
        st.xp           = save.xp
        st.xp_next      = save.xp_next
        st.stat_points  = int(save.stat_points)
        st.strength     = int(save.strength)
        st.dexterity    = int(save.dexterity)
        st.science      = int(save.science)
        st.base_hp      = save.base_hp
        st.base_energy  = save.base_energy
        st.base_speed   = save.base_speed
    }

    if world_has_component(w, pid, .Health) {
        h        := comp_get(w, pid, .Health, HealthComp)
        h.current = save.current_hp
        h.energy  = save.current_energy
        h.shield  = save.current_shield
    }

    if world_has_component(w, pid, .Wallet) {
        comp_get(w, pid, .Wallet, WalletComp).gold = int(save.wallet_gold)
    }

    if world_has_component(w, pid, .MutationContainer) {
        mc         := comp_get(w, pid, .MutationContainer, MutationContainerComp)
        mc.serums   = int(save.mut_serums)
        for i in 0..<int(save.mut_count) {
            mutation_restore_direct(w, pid, MutationType(save.mut_types[i]))
        }
    }

    if !world_has_component(w, pid, .Inventory) { return }

    for i in 0..<int(save.item_count) {
        rec     := save.items[i]
        item_id := _load_spawn_saved_item(w, &save.items[i])
        if item_id == INVALID_ENTITY { continue }
        inv     := comp_get(w, pid, .Inventory, InventoryComp)

        if rec.is_equipped == 1 {
            slot_idx := int(rec.equip_slot_idx)
            if slot_idx >= 0 && slot_idx < EQUIP_SLOT_COUNT {
                slot      := EquipSlot(slot_idx)
                item_comp := comp_get(w, item_id, .Item, ItemComp)
                is_ab_slot := slot >= .Ability1 && slot <= .Ability4
                if is_ab_slot && item_comp.ability_type == .None {
                    if col, row, ok := backpack_find_free(inv, item_comp); ok {
                        backpack_place(inv, item_comp, item_id, col, row)
                    }
                } else {
                    inv.equipped[slot_idx] = item_id
                }
            }
        } else {
            item_comp := comp_get(w, item_id, .Item, ItemComp)
            backpack_place(inv, item_comp, item_id, int(rec.pack_x), int(rec.pack_y))
        }
    }
}

load_player :: proc(w: ^World, pid: int) -> bool {
    if g_active_slot < 0 || g_active_slot >= MAX_CHAR_SLOTS { return false }

    slot := &g_char_save.slots[g_active_slot]
    if slot.exists == 0 { return false }

    save := slot.player
    if save.magic   != SAVE_MAGIC   { return false }
    if save.version != SAVE_VERSION { return false }

    char_idx  := int(save.character)
    stems_ld  := PLAYER_STEMS
    if char_idx < 0 || char_idx >= len(stems_ld) { char_idx = 0 }
    g_player_stem    = stems_ld[char_idx]
    g_lifetime_stats = save.lifetime
    if save.version >= 7 {
        g_quest_completed[g_session.local_slot] = save.quest_completed
    } else {
        g_quest_completed[g_session.local_slot] = 0
    }

    st := local_stash()
    st^ = stash_make_empty()
    st.gold   = int(save.stash_gold)
    st.serums = int(save.stash_serums)
    for i in 0..<int(save.stash_item_count) {
        if st.item_count >= STASH_MAX_ITEMS { break }
        item_id := _load_spawn_saved_item(w, &save.stash_items[i])
        if item_id == INVALID_ENTITY { continue }
        item := comp_get(w, item_id, .Item, ItemComp)
        col := int(save.stash_items[i].pack_x)
        row := int(save.stash_items[i].pack_y)
        if !stash_can_place(item, col, row) {
            col, row, _ = stash_find_free(item)
        }
        if !stash_place_item(w, item_id, col, row) {
            world_destroy_entity(w, item_id)
        }
    }

    _apply_player_save(w, pid, &save)
    ensure_base_flasks(w, pid)
    return true
}

load_player_from_bytes :: proc(w: ^World, pid: int, data: []u8) -> bool {
    if len(data) < size_of(PlayerSaveFile) { return false }
    save := (^PlayerSaveFile)(raw_data(data))^
    if save.magic != SAVE_MAGIC || save.version != SAVE_VERSION { return false }
    _apply_player_save(w, pid, &save)
    return true
}

@(private = "file")
_load_spawn_saved_item :: proc(w: ^World, rec: ^SavedItem) -> int {
    item_id := world_create_entity(w)
    if item_id == INVALID_ENTITY { return INVALID_ENTITY }

    item := item_empty()
    item.slot               = EquipSlot(rec.slot)
    item.rarity             = ItemRarity(rec.rarity)
    item.mutation_type      = MutationType(rec.mutation_type)

    raw_at := rec.ability_type
    if int(raw_at) >= len(ABILITY_DEFS) { raw_at = 0 }
    item.ability_type       = AbilityType(raw_at)
    item.ability_level      = max(1, rec.ability_level)
    item.serum_value        = int(rec.serum_value)
    item.grid_w             = int(rec.grid_w)
    item.grid_h             = int(rec.grid_h)
    item.req_str            = rec.req_str
    item.req_dex            = rec.req_dex
    item.req_sci            = rec.req_sci
    item.affix_count        = rec.affix_count
    item.is_two_handed      = (rec.flags & 0x01) != 0
    item.is_melee           = (rec.flags & 0x02) != 0
    item.weapon_archetype   = WeaponArchetype(rec.weapon_archetype)
    item.melee_damage       = rec.melee_damage
    item.melee_range        = rec.melee_range
    item.melee_spread       = rec.melee_spread
    item.melee_cooldown_max = rec.melee_cooldown_max
    item.base_damage        = rec.base_damage
    item.base_fire_rate     = rec.base_fire_rate
    item.base_ammo_max      = rec.base_ammo_max
    item.base_reload_time   = rec.base_reload_time
    item.base_proj_speed    = rec.base_proj_speed
    item.base_armor         = rec.base_armor
    item.base_shield        = rec.base_shield
    for j in 0..<int(rec.affix_count) {
        item.affixes[j] = Affix{
            type  = AffixType(rec.affixes[j].affix_type),
            value = rec.affixes[j].value,
        }
    }
    comp_set(w, item_id, .Item, item)

    if item.slot == .Flask1 || item.slot == .Flask2 {
        fc := flask_comp_from_save(item.slot, FlaskSize(rec.req_str), item.rarity, int(rec.req_dex))
        comp_set(w, item_id, .Flask, fc)
    }

    rc: RenderConfigComp
    rc.name_len = rec.name_len
    copy(rc.display_name[:], rec.name[:])
    rc.icon_len = rec.icon_len
    copy(rc.icon_name[:], rec.icon[:])
    rc.desc_len = rec.desc_len
    copy(rc.desc[:], rec.desc[:])
    comp_set(w, item_id, .RenderConfig, rc)

    return item_id
}

@(private = "file")
_save_fill_item :: proc(rec: ^SavedItem, item: ^ItemComp) {
    rec.slot               = u8(item.slot)
    rec.rarity             = u8(item.rarity)
    rec.mutation_type      = u8(item.mutation_type)
    rec.ability_type       = u8(item.ability_type)
    rec.ability_level      = item.ability_level
    rec.serum_value        = i32(item.serum_value)
    rec.grid_w             = u8(item.grid_w)
    rec.grid_h             = u8(item.grid_h)
    rec.req_str            = item.req_str
    rec.req_dex            = item.req_dex
    rec.req_sci            = item.req_sci
    rec.affix_count        = item.affix_count
    rec.melee_damage       = item.melee_damage
    rec.melee_range        = item.melee_range
    rec.melee_spread       = item.melee_spread
    rec.melee_cooldown_max = item.melee_cooldown_max
    rec.base_damage        = item.base_damage
    rec.base_fire_rate     = item.base_fire_rate
    rec.base_ammo_max      = item.base_ammo_max
    rec.base_reload_time   = item.base_reload_time
    rec.base_proj_speed    = item.base_proj_speed
    rec.base_armor         = item.base_armor
    rec.base_shield        = item.base_shield
    flags: u8
    if item.is_two_handed { flags |= 0x01 }
    if item.is_melee      { flags |= 0x02 }
    rec.flags            = flags
    rec.weapon_archetype = u8(item.weapon_archetype)
    for i in 0..<int(item.affix_count) {
        rec.affixes[i] = SavedAffix{
            affix_type = u8(item.affixes[i].type),
            value      = item.affixes[i].value,
        }
    }
}

@(private = "file")
_save_fill_flask :: proc(rec: ^SavedItem, fc: ^FlaskComp) {
    rec.req_str = u8(fc.size)
    rec.req_dex = u8(min(fc.charges, 255))
}

@(private = "file")
_save_fill_render :: proc(rec: ^SavedItem, rc: ^RenderConfigComp) {
    rec.name_len = rc.name_len
    copy(rec.name[:], rc.display_name[:])
    rec.icon_len = rc.icon_len
    copy(rec.icon[:], rc.icon_name[:])
    rec.desc_len = rc.desc_len
    copy(rec.desc[:], rc.desc[:])
}
