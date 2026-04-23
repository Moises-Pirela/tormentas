package main

// =============================================================================
// ITEMS — Backpack grid helpers and loot drop spawning
//
// Backpack grid rules:
//   • Items occupy a rectangular footprint of (grid_w × grid_h) cells.
//   • Every cell in that footprint stores the item's entity ID.
//   • Empty cells store INVALID_ENTITY (-1).
//   • pack_x / pack_y on ItemComp record the top-left cell of the placed item.
//     Both are -1 when the item is not in the backpack.
//
// Pointer safety: spawn_loot_drop calls world_create_entity which may resize
// backing arrays.  Callers must not hold live component pointers across a call.
// =============================================================================

import "core:math/rand"
import cw "clockwork"

@(private = "file")
affix_count_for_rarity :: proc(r: cw.ItemRarity) -> int {
    switch r {
    case .Normal:    return 1
    case .Rare:      return 2
    case .Epic:      return 3
    case .Legendary: return 4
    case .Unique:    return 4
    }
    return 0
}

@(private = "file")
affix_value_for_rarity :: proc(r: cw.ItemRarity) -> f32 {
    switch r {
    case .Normal:    return 0.01 + rand.float32() * 0.05 // 1-5%
    case .Rare:      return 0.06 + rand.float32() * 0.06   // 6–12%
    case .Epic:      return 0.10 + rand.float32() * 0.07   // 10–17%
    case .Legendary: return 0.15 + rand.float32() * 0.08   // 15–23%
    case .Unique:    return 0.22 + rand.float32() * 0.08   // 22–30%
    }
    return 0
}

roll_affixes :: proc(item: ^cw.ItemComp) {
    if item == nil {
        return
    }

    item.affix_count = 0
    for i in 0..<len(item.affixes) {
        item.affixes[i] = {}
    }

    count := affix_count_for_rarity(item.rarity)
    if count <= 0 {
        return
    }

    armor_pool  := [4]cw.AffixType{
        .BonusHP,
        .Armor,
        .BonusMoveSpeed,
        .BonusEnergy,
    }

    weapon_pool := [3]cw.AffixType{
        .BonusDamage,
        .BonusFireRate,
        .BonusReloadSpeed,
    }

    melee_pool := [3]cw.AffixType{
        .BonusDamage,
        .BonusMoveSpeed,
        .BonusHP,
    }

    pool_slice: []cw.AffixType

    switch item.slot {
    case .Head, .Chest, .Boots:
        pool_slice = armor_pool[:]

    case .WeaponPrimary, .WeaponOffhand:
        if item.is_melee {
            pool_slice = melee_pool[:]
        } else {
            pool_slice = weapon_pool[:]
        }

    case .Consumable, .Ability1, .Ability2, .Ability3, .Ability4:
        return
    }

    if len(pool_slice) == 0 {
        return
    }

    pool_copy := make(
        []cw.AffixType,
        len(pool_slice),
        context.temp_allocator,
    )
    copy(pool_copy, pool_slice)

    for i := len(pool_copy) - 1; i > 0; i -= 1 {
        j := rand.int_max(i + 1) // assumes [0, n)
        pool_copy[i], pool_copy[j] = pool_copy[j], pool_copy[i]
    }

    n := min(count, len(pool_copy), len(item.affixes))

    for i in 0..<n {
        affix_type := pool_copy[i]

        item.affixes[i] = cw.Affix{
            type  = affix_type,
            value = affix_value_for_rarity(item.rarity),
        }
    }

    item.affix_count = u8(n)
}

roll_rarity :: proc() -> cw.ItemRarity {
    r := rand.int_max(100)
    switch {
    case r < 50: return .Normal
    case r < 75: return .Rare
    case r < 90: return .Epic
    case r < 98: return .Legendary
    case:        return .Unique
    }
    return .Normal
}

BACKPACK_CELL_SIZE :: 36

backpack_can_place :: proc(
    inv:       ^cw.InventoryComp,
    item:      ^cw.ItemComp,
    col, row:  int,
    except_id: int = cw.INVALID_ENTITY,
) -> bool {
    if col < 0 || row < 0                         { return false }
    if col + item.grid_w > cw.BACKPACK_COLS       { return false }
    if row + item.grid_h > cw.BACKPACK_ROWS       { return false }

    for dy in 0..<item.grid_h {
        for dx in 0..<item.grid_w {
            cell := inv.backpack[(row + dy) * cw.BACKPACK_COLS + (col + dx)]
            if cell != cw.INVALID_ENTITY && cell != except_id { return false }
        }
    }
    return true
}

backpack_place :: proc(inv: ^cw.InventoryComp, item: ^cw.ItemComp, item_id: int, col, row: int) {
    item.pack_x = col
    item.pack_y = row
    for dy in 0..<item.grid_h {
        for dx in 0..<item.grid_w {
            inv.backpack[(row + dy) * cw.BACKPACK_COLS + (col + dx)] = item_id
        }
    }
}

backpack_remove :: proc(inv: ^cw.InventoryComp, item: ^cw.ItemComp) {
    if item.pack_x < 0 { return }
    for dy in 0..<item.grid_h {
        for dx in 0..<item.grid_w {
            inv.backpack[(item.pack_y + dy) * cw.BACKPACK_COLS + (item.pack_x + dx)] = cw.INVALID_ENTITY
        }
    }
    item.pack_x = -1
    item.pack_y = -1
}

backpack_find_free :: proc(inv: ^cw.InventoryComp, item: ^cw.ItemComp) -> (col, row: int, ok: bool) {
    for r in 0..<cw.BACKPACK_ROWS {
        for c in 0..<cw.BACKPACK_COLS {
            if backpack_can_place(inv, item, c, r) {
                return c, r, true
            }
        }
    }
    return 0, 0, false
}

@(private = "file")
LootDef :: struct {
    name:               string,
    icon:               string,
    slot:               cw.EquipSlot,
    grid_w:             int,
    grid_h:             int,
    mutation_type:      cw.MutationType,
    serum_value:        int,
    desc:               string,
    req_str:            u8,
    req_dex:            u8,
    req_sci:            u8,
    is_two_handed:      bool,
    is_melee:           bool,
    melee_damage:       f32,
    melee_range:        f32,
    melee_spread:       f32,   // half-angle in radians
    melee_cooldown_max: f32,
}

LOOT_TABLE := [?]LootDef{
    // ---- Armor ----
    {
        name = "Reliquia Corrupta", icon = "reliquia", slot = .Head, grid_w = 2, grid_h = 1,
        desc = "A cursed medallion. Its wearer hears whispers.",
        req_str = 0, req_dex = 0, req_sci = 0,
    },
    {
        name = "Coraza de Cuero", icon = "coraza", slot = .Chest, grid_w = 2, grid_h = 2,
        desc = "Hardened leather vest. Absorbs punishment.",
        req_str = 2, req_dex = 0, req_sci = 0,
    },
    {
        name = "Coraza de Hierro", icon = "coraza", slot = .Chest, grid_w = 2, grid_h = 2,
        desc = "Heavy iron breastplate. Turns aside bullets and blades alike.",
        req_str = 4, req_dex = 0, req_sci = 0,
    },
    {
        name = "Cartucho", icon = "cartucho", slot = .Chest, grid_w = 1, grid_h = 1,
        desc = "Reinforced ammo pouch. Speeds up reloads.",
        req_str = 0, req_dex = 1, req_sci = 0,
    },
    {
        name = "Fragmento Etéreo", icon = "fragmento", slot = .Boots, grid_w = 1, grid_h = 2,
        desc = "Crystallised ether. Enhances footwork.",
        req_str = 0, req_dex = 2, req_sci = 1,
    },
    {
        name = "Botas de Coyote", icon = "botas", slot = .Boots, grid_w = 2, grid_h = 1,
        desc = "Coyote-hide boots. Light and swift.",
        req_str = 0, req_dex = 2, req_sci = 0,
    },
    {
        name = "Fetiche de Hueso", icon = "fetiche", slot = .Head, grid_w = 2, grid_h = 2,
        desc = "Bone idol ward. Enemies hesitate to strike.",
        req_str = 3, req_dex = 0, req_sci = 0,
    },
    // ---- Ranged weapons ----
    {
        name = "Percutor Reforzado", icon = "mod_damage", slot = .WeaponPrimary, grid_w = 1, grid_h = 1,
        desc = "Heavier striker. Increases weapon damage.",
        req_str = 0, req_dex = 1, req_sci = 0,
    },
    {
        name = "Resorte Ligero", icon = "mod_speed", slot = .WeaponPrimary, grid_w = 1, grid_h = 1,
        desc = "Spring-loaded mechanism. Boosts fire rate and reload.",
        req_str = 0, req_dex = 2, req_sci = 0,
    },
    {
        name = "Cargador Extendido", icon = "mod_ammo", slot = .WeaponPrimary, grid_w = 2, grid_h = 1,
        desc = "Bulky extended magazine. Both hands needed to operate.",
        req_str = 0, req_dex = 1, req_sci = 1,
        is_two_handed = true,
    },
    // ---- Melee weapons ----
    {
        name = "Machete del Desierto", icon = "mod_damage", slot = .WeaponPrimary, grid_w = 2, grid_h = 1,
        desc = "A long, heavy blade. Silences enemies up close.",
        req_str = 2, req_dex = 0, req_sci = 0,
        is_melee = true, melee_damage = 30, melee_range = 72, melee_spread = 0.65, melee_cooldown_max = 0.55,
    },
    {
        name = "Hacha de Guerra", icon = "fetiche", slot = .WeaponPrimary, grid_w = 2, grid_h = 2,
        desc = "Brutal war axe. Massive damage, slow swing. Both hands required.",
        req_str = 4, req_dex = 0, req_sci = 0,
        is_two_handed = true,
        is_melee = true, melee_damage = 65, melee_range = 80, melee_spread = 0.45, melee_cooldown_max = 1.1,
    },
    {
        name = "Navaja Veloz", icon = "mod_speed", slot = .WeaponPrimary, grid_w = 1, grid_h = 1,
        desc = "A swift folding blade. Strikes faster than the eye.",
        req_str = 0, req_dex = 3, req_sci = 0,
        is_melee = true, melee_damage = 14, melee_range = 56, melee_spread = 0.8, melee_cooldown_max = 0.28,
    },
    // ---- Necrotic Serum ----
    {
        name = "Suero Necrótico", icon = "serum", slot = .Consumable,
        serum_value = 1,
        desc = "A vial of necrotic fluid. Use it to graft mutations.",
    },
    {
        name = "Suero Necrótico x3", icon = "serum", slot = .Consumable,
        serum_value = 3,
        desc = "Three vials of necrotic fluid. Enough to graft a major mutation.",
    },
}

spawn_loot_drop :: proc(w: ^cw.World, world_pos: [3]f32, seed: u64) {
    rng_state                := rand.create(seed)
    context.random_generator  = rand.default_random_generator(&rng_state)

    def := &LOOT_TABLE[rand.int_max(len(LOOT_TABLE))]

    item_id := cw.world_create_entity(w)

    cw.world_set_transform(w, item_id, cw.TransformComp{
        position = world_pos,
    })

    item_comp := cw.item_empty()
    item_comp.slot               = def.slot
    item_comp.rarity             = roll_rarity()
    item_comp.mutation_type      = def.mutation_type
    item_comp.serum_value        = def.serum_value
    item_comp.grid_w             = def.grid_w
    item_comp.grid_h             = def.grid_h
    item_comp.req_str            = def.req_str
    item_comp.req_dex            = def.req_dex
    item_comp.req_sci            = def.req_sci
    item_comp.is_two_handed      = def.is_two_handed
    item_comp.is_melee           = def.is_melee
    item_comp.melee_damage       = def.melee_damage
    item_comp.melee_range        = def.melee_range
    item_comp.melee_spread       = def.melee_spread
    item_comp.melee_cooldown_max = def.melee_cooldown_max
    roll_affixes(&item_comp)
    cw.world_set_item(w, item_id, item_comp)

    rc: cw.RenderConfigComp
    cw.render_config_set_name(&rc, def.name)
    cw.render_config_set_icon(&rc, def.icon)
    cw.render_config_set_desc(&rc, def.desc)
    cw.world_set_render_config(w, item_id, rc)

    cw.world_set_ground_item(w, item_id)
    cw.world_set_fog_of_war(w, item_id)
}

loot_seed :: proc(tick: u64, entity_id: int) -> u64 {
    h := (u64(entity_id) + 1) * 6364136223846793005 ~ (tick * 2685821657736338717)
    h ~= h >> 33
    h  *= 0xff51afd7ed558ccd
    h ~= h >> 33
    return h
}


