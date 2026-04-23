package main

import "core:os"
import cw "clockwork"

SAVE_PATH      :: "save/player.bin"
SAVE_MAGIC     :: u32(0x544F524D)
SAVE_VERSION   :: u16(3)
SAVE_MAX_ITEMS :: 64

PlayerLifetimeStats :: struct #packed {
    successful_raids: i32,
    enemies_killed:   i32,
    deaths:           i32,
    max_extract_gold: i32,
    _reserved:        [12]i32,
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
    serum_value:        i32,
    grid_w:             u8,
    grid_h:             u8,
    req_str:            u8,
    req_dex:            u8,
    req_sci:            u8,
    affix_count:        u8,
    flags:              u8,
    _pad2:              u8,
    melee_damage:       f32,
    melee_range:        f32,
    melee_spread:       f32,
    melee_cooldown_max: f32,
    affixes:            [cw.MAX_AFFIXES]SavedAffix,

    name_len: u8,
    name:     [cw.RENDER_NAME_CAP]u8,
    icon_len: u8,
    icon:     [cw.RENDER_ICON_CAP]u8,
    desc_len: u8,
    desc:     [cw.RENDER_DESC_CAP]u8,
}

PlayerSaveFile :: struct #packed {
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
    wallet_gold:    i32,

    stash_gold:     i32,
    stash_serums:   i32,

    item_count:     u16,
    _pad2:          u16,

    lifetime:       PlayerLifetimeStats,

    mut_serums:     i32,
    mut_count:      u8,
    _mut_pad:       [3]u8,
    mut_types:      [cw.MAX_MUTATION_SLOTS]u8,
    _mut_align:     u8,

    items:          [SAVE_MAX_ITEMS]SavedItem,
}

strip_player_carried :: proc(w: ^cw.World, pid: int) {
    if !cw.world_is_valid(w, pid)                  { return }
    if !cw.world_has_component(w, pid, .Inventory) { return }

    inv := cw.world_get_inventory(w, pid)
    for &slot in inv.equipped { slot = cw.INVALID_ENTITY }
    for &cell in inv.backpack  { cell = cw.INVALID_ENTITY }

    if cw.world_has_component(w, pid, .Wallet) {
        cw.world_get_wallet(w, pid).gold = 0
    }
}

compute_extract_value :: proc(w: ^cw.World, pid: int) -> int {
    total := 0
    if cw.world_has_component(w, pid, .Wallet) {
        total += cw.world_get_wallet(w, pid).gold
    }
    if !cw.world_has_component(w, pid, .Inventory) { return total }
    inv  := cw.world_get_inventory(w, pid)
    seen: map[int]bool
    defer delete(seen)
    for eid in inv.equipped {
        if eid == cw.INVALID_ENTITY               { continue }
        if seen[eid]                              { continue }
        seen[eid] = true
        if !cw.world_has_component(w, eid, .Item) { continue }
        total += item_gold_value(cw.world_get_item(w, eid))
    }
    for cell in inv.backpack {
        if cell == cw.INVALID_ENTITY               { continue }
        if seen[cell]                              { continue }
        seen[cell] = true
        if !cw.world_has_component(w, cell, .Item) { continue }
        item := cw.world_get_item(w, cell)
        if item.serum_value > 0                    { continue }
        total += item_gold_value(item)
    }
    return total
}

save_player :: proc(w: ^cw.World, pid: int) {
    save: PlayerSaveFile
    save.magic    = SAVE_MAGIC
    save.version  = SAVE_VERSION
    save.lifetime = g_lifetime_stats
    
    os.make_directory("save")

    if cw.world_has_component(w, pid, .Stats) {
        st              := cw.world_get_stats(w, pid)
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

    if cw.world_has_component(w, pid, .Health) {
        h                   := cw.world_get_health(w, pid)
        save.current_hp      = h.current
        save.current_energy  = h.energy
    }

    if cw.world_has_component(w, pid, .Wallet) {
        save.wallet_gold = i32(cw.world_get_wallet(w, pid).gold)
    }

    save.stash_gold   = i32(g_stash.gold)
    save.stash_serums = i32(g_stash.serums)

    if cw.world_has_component(w, pid, .MutationContainer) {
        mc := cw.world_get_mutation(w, pid)
        save.mut_serums = i32(mc.serums)
        save.mut_count  = u8(mc.entity_count)
        for i in 0..<mc.entity_count {
            eid := mc.entities[i]
            if !cw.world_is_valid(w, eid)              { continue }
            if !cw.world_has_component(w, eid, .Mut)   { continue }
            save.mut_types[i] = u8(cw.world_get_mut(w, eid).type_id)
        }
    }

    if cw.world_has_component(w, pid, .Inventory) {
        inv := cw.world_get_inventory(w, pid)

        for slot_idx in 0..<cw.EQUIP_SLOT_COUNT {
            eid := inv.equipped[slot_idx]
            if !cw.world_is_valid(w, eid)             { continue }
            if !cw.world_has_component(w, eid, .Item) { continue }
            if save.item_count >= SAVE_MAX_ITEMS       { break }

            rec := &save.items[save.item_count]
            save.item_count += 1
            rec.is_equipped    = 1
            rec.equip_slot_idx = u8(slot_idx)
            _save_fill_item(rec, cw.world_get_item(w, eid))
            if cw.world_has_component(w, eid, .RenderConfig) {
                _save_fill_render(rec, cw.world_get_render_config(w, eid))
            }
        }

        seen: map[int]bool
        defer delete(seen)
        for cell in inv.backpack {
            if cell == cw.INVALID_ENTITY                { continue }
            if seen[cell]                               { continue }
            seen[cell] = true
            if !cw.world_has_component(w, cell, .Item) { continue }
            if save.item_count >= SAVE_MAX_ITEMS        { break }

            rec  := &save.items[save.item_count]
            save.item_count += 1
            item := cw.world_get_item(w, cell)
            rec.is_equipped = 0
            rec.pack_x      = i16(item.pack_x)
            rec.pack_y      = i16(item.pack_y)
            _save_fill_item(rec, item)
            if cw.world_has_component(w, cell, .RenderConfig) {
                _save_fill_render(rec, cw.world_get_render_config(w, cell))
            }
        }
    }

    data := (^[size_of(PlayerSaveFile)]u8)(&save)^
    os.write_entire_file(SAVE_PATH, data[:])
}

load_player :: proc(w: ^cw.World, pid: int) -> bool {
    raw, ok := os.read_entire_file(SAVE_PATH)
    if !ok { return false }
    defer delete(raw)

    if len(raw) < size_of(PlayerSaveFile) { return false }

    save := (^PlayerSaveFile)(raw_data(raw))^
    if save.magic   != SAVE_MAGIC   { return false }
    if save.version != SAVE_VERSION { return false }

    g_lifetime_stats = save.lifetime

    if cw.world_has_component(w, pid, .Stats) {
        st             := cw.world_get_stats(w, pid)
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

    if cw.world_has_component(w, pid, .Health) {
        h        := cw.world_get_health(w, pid)
        h.current = save.current_hp
        h.energy  = save.current_energy
    }

    if cw.world_has_component(w, pid, .Wallet) {
        cw.world_get_wallet(w, pid).gold = int(save.wallet_gold)
    }

    g_stash.gold   = int(save.stash_gold)
    g_stash.serums = int(save.stash_serums)

    if cw.world_has_component(w, pid, .MutationContainer) {
        mc         := cw.world_get_mutation(w, pid)
        mc.serums   = int(save.mut_serums)
        for i in 0..<int(save.mut_count) {
            mutation_restore_direct(w, pid, cw.MutationType(save.mut_types[i]))
        }
    }

    if !cw.world_has_component(w, pid, .Inventory) { return true }

    for i in 0..<int(save.item_count) {
        rec     := save.items[i]
        item_id := cw.world_create_entity(w)
        inv     := cw.world_get_inventory(w, pid)

        item := cw.item_empty()
        item.slot               = cw.EquipSlot(rec.slot)
        item.rarity             = cw.ItemRarity(rec.rarity)
        item.mutation_type      = cw.MutationType(rec.mutation_type)
        item.ability_type       = cw.AbilityType(rec.ability_type)
        item.serum_value        = int(rec.serum_value)
        item.grid_w             = int(rec.grid_w)
        item.grid_h             = int(rec.grid_h)
        item.req_str            = rec.req_str
        item.req_dex            = rec.req_dex
        item.req_sci            = rec.req_sci
        item.affix_count        = rec.affix_count
        item.is_two_handed      = (rec.flags & 0x01) != 0
        item.is_melee           = (rec.flags & 0x02) != 0
        item.melee_damage       = rec.melee_damage
        item.melee_range        = rec.melee_range
        item.melee_spread       = rec.melee_spread
        item.melee_cooldown_max = rec.melee_cooldown_max
        for j in 0..<int(rec.affix_count) {
            item.affixes[j] = cw.Affix{
                type  = cw.AffixType(rec.affixes[j].affix_type),
                value = rec.affixes[j].value,
            }
        }
        cw.world_set_item(w, item_id, item)

        rc: cw.RenderConfigComp
        rc.name_len = rec.name_len
        copy(rc.display_name[:], rec.name[:])
        rc.icon_len = rec.icon_len
        copy(rc.icon_name[:], rec.icon[:])
        rc.desc_len = rec.desc_len
        copy(rc.desc[:], rec.desc[:])
        cw.world_set_render_config(w, item_id, rc)

        if rec.is_equipped == 1 {
            slot_idx := int(rec.equip_slot_idx)
            if slot_idx >= 0 && slot_idx < cw.EQUIP_SLOT_COUNT {
                inv.equipped[slot_idx] = item_id
            }
        } else {
            item_comp := cw.world_get_item(w, item_id)
            backpack_place(inv, item_comp, item_id, int(rec.pack_x), int(rec.pack_y))
        }
    }

    return true
}

@(private = "file")
_save_fill_item :: proc(rec: ^SavedItem, item: ^cw.ItemComp) {
    rec.slot               = u8(item.slot)
    rec.rarity             = u8(item.rarity)
    rec.mutation_type      = u8(item.mutation_type)
    rec.ability_type       = u8(item.ability_type)
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
    flags: u8
    if item.is_two_handed { flags |= 0x01 }
    if item.is_melee      { flags |= 0x02 }
    rec.flags = flags
    for i in 0..<int(item.affix_count) {
        rec.affixes[i] = SavedAffix{
            affix_type = u8(item.affixes[i].type),
            value      = item.affixes[i].value,
        }
    }
}

@(private = "file")
_save_fill_render :: proc(rec: ^SavedItem, rc: ^cw.RenderConfigComp) {
    rec.name_len = rc.name_len
    copy(rec.name[:], rc.display_name[:])
    rec.icon_len = rc.icon_len
    copy(rec.icon[:], rc.icon_name[:])
    rec.desc_len = rc.desc_len
    copy(rec.desc[:], rc.desc[:])
}
