package main


import "core:math"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:fmt"
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
    case .Normal:    return 0.01 + rand.float32() * 0.05
    case .Rare:      return 0.06 + rand.float32() * 0.06
    case .Epic:      return 0.10 + rand.float32() * 0.07
    case .Legendary: return 0.15 + rand.float32() * 0.08
    case .Unique:    return 0.22 + rand.float32() * 0.08
    }
    return 0
}


@(private = "file")
affix_stat_bonus_for_rarity :: proc(r: cw.ItemRarity) -> f32 {
    switch r {
    case .Normal:    return 1
    case .Rare:      return 1 + f32(rand.int_max(2))
    case .Epic:      return 2 + f32(rand.int_max(2))
    case .Legendary: return 3 + f32(rand.int_max(2))
    case .Unique:    return 4 + f32(rand.int_max(2))
    }
    return 1
}


@(private = "file")
affix_energy_regen_for_rarity :: proc(r: cw.ItemRarity) -> f32 {
    switch r {
    case .Normal:    return 1 + rand.float32() * 2
    case .Rare:      return 3 + rand.float32() * 2
    case .Epic:      return 5 + rand.float32() * 3
    case .Legendary: return 7 + rand.float32() * 4
    case .Unique:    return 10 + rand.float32() * 4
    }
    return 1
}


@(private = "file")
affix_resist_for_rarity :: proc(r: cw.ItemRarity) -> f32 {
    switch r {
    case .Normal:    return 0.05 + rand.float32() * 0.05
    case .Rare:      return 0.10 + rand.float32() * 0.07
    case .Epic:      return 0.15 + rand.float32() * 0.08
    case .Legendary: return 0.20 + rand.float32() * 0.10
    case .Unique:    return 0.25 + rand.float32() * 0.10
    }
    return 0.05
}


@(private = "file")
FLASK_STATS := [cw.FlaskKind][cw.FlaskSize][2][3]f32{

    .Health = {
        .Small  = { {  60, 4, 3 }, { 100, 4, 3 } },
        .Medium = { { 140, 5, 2 }, { 220, 5, 2 } },
        .Large  = { { 280, 6, 1 }, { 450, 6, 1 } },
    },

    .Energy = {
        .Small  = { {  35, 3, 3 }, {  55, 3, 3 } },
        .Medium = { {  80, 4, 2 }, { 125, 4, 2 } },
        .Large  = { { 160, 5, 1 }, { 250, 5, 1 } },
    },
}

@(private = "file")
FLASK_SIZE_NAMES := [cw.FlaskSize]string{ .Small = "Small", .Medium = "Medium", .Large = "Large" }
@(private = "file")
FLASK_KIND_NAMES := [cw.FlaskKind]string{ .Health = "Health", .Energy = "Energy" }


create_flask_item :: proc(w: ^cw.World, kind: cw.FlaskKind, size: cw.FlaskSize, rarity: cw.ItemRarity) -> int {
    r := rarity if rarity <= .Rare else cw.ItemRarity.Rare
    ri := int(r)
    stats := FLASK_STATS[kind][size][ri]
    recover_amount   := stats[0]
    recover_duration := stats[1]
    max_charges      := i32(stats[2])

    flask_slot := cw.EquipSlot.Flask1 if kind == .Health else cw.EquipSlot.Flask2

    id := cw.world_create_entity(w)
    cw.world_set_item(w, id, cw.ItemComp{
        slot      = flask_slot,
        rarity    = r,
        grid_w    = 1,
        grid_h    = 2,
        pack_x    = -1,
        pack_y    = -1,
    })
    cw.world_set_flask(w, id, cw.FlaskComp{
        kind             = kind,
        size             = size,
        recover_amount   = recover_amount,
        recover_duration = recover_duration,
        charges          = max_charges,
        max_charges      = max_charges,
    })
    return id
}


flask_comp_from_save :: proc(slot: cw.EquipSlot, size: cw.FlaskSize, rarity: cw.ItemRarity, saved_charges: int) -> cw.FlaskComp {
    kind := cw.FlaskKind.Health if slot == .Flask1 else cw.FlaskKind.Energy
    ri   := min(int(rarity), 1)
    si   := clamp(int(size), 0, 2)
    stats  := FLASK_STATS[kind][cw.FlaskSize(si)][ri]
    max_ch := i32(stats[2])
    ch     := i32(saved_charges)
    if ch <= 0 || ch > max_ch { ch = max_ch }
    return cw.FlaskComp{
        kind             = kind,
        size             = cw.FlaskSize(si),
        recover_amount   = stats[0],
        recover_duration = stats[1],
        charges          = ch,
        max_charges      = max_ch,
    }
}

roll_affixes :: proc(item: ^cw.ItemComp) {
    if item == nil { return }


    base_count := int(item.affix_count)
    for i in base_count..<len(item.affixes) { item.affixes[i] = {} }

    target := affix_count_for_rarity(item.rarity)
    to_add := max(0, target - base_count)
    if to_add == 0 || base_count >= len(item.affixes) { return }


    armor_pool  := [?]cw.AffixType{
        .BonusHP, .Armor, .BonusMoveSpeed, .BonusEnergy, .HealthRegen,
        .BonusStrength, .BonusDexterity, .BonusScience,
        .BonusEnergyRegen, .ReduceEnergyCost,
        .ResistPhysical, .ResistNecrotic, .ResistFire, .ResistGalvanic, .ResistPoison,
    }
    weapon_pool := [?]cw.AffixType{
        .BonusDamage, .BonusFireRate, .BonusReloadSpeed,
        .BonusProjSpeed, .BonusPierce, .BonusAmmo,
        .BonusDexterity, .BonusScience, .ReduceEnergyCost,
        .ResistPhysical, .ResistFire, .ResistPoison,
    }
    melee_pool  := [?]cw.AffixType{
        .BonusDamage, .BonusMoveSpeed, .BonusHP,
        .BonusMeleeDamage, .BonusMeleeRange, .BonusMeleeSpeed,
        .BonusStrength, .BonusDexterity, .ReduceEnergyCost,
        .ResistPhysical, .ResistNecrotic, .ResistGalvanic,
    }

    pool_slice: []cw.AffixType
    switch item.slot {
    case .Head, .Chest, .Boots:             pool_slice = armor_pool[:]
    case .WeaponPrimary, .WeaponOffhand:
        pool_slice = melee_pool[:] if item.is_melee else weapon_pool[:]
    case .Consumable, .Ability1, .Ability2, .Ability3, .Ability4,
         .Flask1, .Flask2:
        return
    }
    if len(pool_slice) == 0 { return }


    pool_copy := make([]cw.AffixType, len(pool_slice), context.temp_allocator)
    pool_len  := 0
    for at in pool_slice {
        already := false
        for i in 0..<base_count {
            if item.affixes[i].type == at { already = true; break }
        }
        if !already { pool_copy[pool_len] = at; pool_len += 1 }
    }
    pool_copy = pool_copy[:pool_len]


    for i := len(pool_copy) - 1; i > 0; i -= 1 {
        j := rand.int_max(i + 1)
        pool_copy[i], pool_copy[j] = pool_copy[j], pool_copy[i]
    }

    n := min(to_add, len(pool_copy), len(item.affixes) - base_count)
    for i in 0..<n {
        at  := pool_copy[i]
        val : f32
        #partial switch at {
        case .BonusPierce:
            val = 1.0
        case .BonusStrength, .BonusDexterity, .BonusScience:
            val = affix_stat_bonus_for_rarity(item.rarity)
        case .BonusEnergyRegen:
            val = affix_energy_regen_for_rarity(item.rarity)
        case .ResistPhysical, .ResistNecrotic, .ResistFire, .ResistGalvanic, .ResistPoison:

            val = affix_resist_for_rarity(item.rarity)
        case:
            val = affix_value_for_rarity(item.rarity)
        }
        item.affixes[base_count + i] = cw.Affix{ type = at, value = val }
    }
    item.affix_count = u8(base_count + n)
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


LootRaritySet :: bit_set[cw.ItemRarity]


MAX_BASE_AFFIXES :: 4

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
    melee_spread:       f32,
    melee_cooldown_max: f32,
    rarities:           LootRaritySet,
    roll_weight:        int,
    base_affixes:       [MAX_BASE_AFFIXES]cw.Affix,
    base_affix_count:   u8,
    weapon_archetype:   cw.WeaponArchetype,


    base_damage:      f32,
    base_fire_rate:   f32,
    base_ammo_max:    u8,
    base_reload_time: f32,
    base_proj_speed:  f32,
    base_armor:       f32,
    base_shield:      f32,
}


g_loot_table:      [dynamic]LootDef
g_loot_file_data:  []u8

loot_table_load :: proc(path: string) -> bool {
    data, ok := os.read_entire_file(path)
    if !ok {
        fmt.eprintln("loot_table_load: could not read", path)
        return false
    }
    g_loot_file_data = data

    text  := string(data)
    start := 0
    first := true
    fields: [dynamic]string
    defer delete(fields)

    for i in 0..=len(text) {
        if i == len(text) || text[i] == '\n' {
            line := text[start:i]
            if len(line) > 0 && line[len(line)-1] == '\r' {
                line = line[:len(line)-1]
            }
            start = i + 1
            if first { first = false; continue }
            if len(line) == 0 { continue }

            _csv_parse_line(line, &fields)
            if len(fields) < 18 { continue }

            def: LootDef
            def.name               = fields[0]
            def.icon               = fields[1]
            def.slot               = _parse_equip_slot(fields[2])
            def.grid_w, _          = strconv.parse_int(fields[3], 10)
            def.grid_h, _          = strconv.parse_int(fields[4], 10)
            def.serum_value, _     = strconv.parse_int(fields[5], 10)
            def.desc               = fields[6]
            { v, _ := strconv.parse_int(fields[7],  10); def.req_str = u8(v) }
            { v, _ := strconv.parse_int(fields[8],  10); def.req_dex = u8(v) }
            { v, _ := strconv.parse_int(fields[9],  10); def.req_sci = u8(v) }
            { v, _ := strconv.parse_int(fields[10], 10); def.is_two_handed = v != 0 }
            { v, _ := strconv.parse_int(fields[11], 10); def.is_melee = v != 0 }
            { v, _ := strconv.parse_f64(fields[12]); def.melee_damage       = f32(v) }
            { v, _ := strconv.parse_f64(fields[13]); def.melee_range        = f32(v) }
            { v, _ := strconv.parse_f64(fields[14]); def.melee_spread       = f32(v) }
            { v, _ := strconv.parse_f64(fields[15]); def.melee_cooldown_max = f32(v) }
            def.rarities           = _parse_rarity_set(fields[16])
            def.roll_weight, _     = strconv.parse_int(fields[17], 10)
            if def.roll_weight <= 0 { def.roll_weight = 1 }
            if len(fields) >= 19 && len(fields[18]) > 0 {
                def.base_affix_count = _parse_affix_list(fields[18], def.base_affixes[:])
            }
            if len(fields) >= 20 && len(fields[19]) > 0 {
                def.weapon_archetype = _parse_weapon_archetype(fields[19])
            }
            if len(fields) >= 21 && len(fields[20]) > 0 {
                v, _ := strconv.parse_f64(fields[20]); def.base_damage = f32(v)
            }
            if len(fields) >= 22 && len(fields[21]) > 0 {
                v, _ := strconv.parse_f64(fields[21]); def.base_fire_rate = f32(v)
            }
            if len(fields) >= 23 && len(fields[22]) > 0 {
                v, _ := strconv.parse_int(fields[22], 10); def.base_ammo_max = u8(v)
            }
            if len(fields) >= 24 && len(fields[23]) > 0 {
                v, _ := strconv.parse_f64(fields[23]); def.base_reload_time = f32(v)
            }
            if len(fields) >= 25 && len(fields[24]) > 0 {
                v, _ := strconv.parse_f64(fields[24]); def.base_proj_speed = f32(v)
            }
            if len(fields) >= 26 && len(fields[25]) > 0 {
                v, _ := strconv.parse_f64(fields[25]); def.base_armor = f32(v)
            }
            if len(fields) >= 27 && len(fields[26]) > 0 {
                v, _ := strconv.parse_f64(fields[26]); def.base_shield = f32(v)
            }

            append(&g_loot_table, def)
        }
    }

    return len(g_loot_table) > 0
}

loot_table_destroy :: proc() {
    delete(g_loot_table)
    if g_loot_file_data != nil {
        delete(g_loot_file_data)
        g_loot_file_data = nil
    }
}


loot_find_by_name :: proc(name: string) -> ^LootDef {
    for &def in g_loot_table {
        if def.name == name { return &def }
    }
    return nil
}


roll_rarity_allowed :: proc(mask: LootRaritySet) -> cw.ItemRarity {


    WEIGHTS := [cw.ItemRarity]int{
        .Normal    = 750,
        .Rare      = 220,
        .Epic      = 8,
        .Legendary = 2,
        .Unique    = 1,
    }
    total := 0
    for r in cw.ItemRarity { if r in mask { total += WEIGHTS[r] } }
    if total == 0 { return .Normal }
    pick := rand.int_max(total)
    acc  := 0
    for r in cw.ItemRarity {
        if r not_in mask { continue }
        acc += WEIGHTS[r]
        if pick < acc { return r }
    }
    return .Normal
}


@(private = "file")
_csv_parse_line :: proc(line: string, fields: ^[dynamic]string) {
    clear(fields)
    i := 0
    for i <= len(line) {
        if i == len(line) {
            append(fields, "")
            break
        }
        if line[i] == '"' {
            i += 1
            start := i
            for i < len(line) && line[i] != '"' { i += 1 }
            append(fields, line[start:i])
            if i < len(line) { i += 1 }
        } else {
            start := i
            for i < len(line) && line[i] != ',' { i += 1 }
            append(fields, line[start:i])
        }
        if i < len(line) && line[i] == ',' { i += 1 } else { break }
    }
}

@(private = "file")
_parse_equip_slot :: proc(s: string) -> cw.EquipSlot {
    switch s {
    case "Head":          return .Head
    case "Chest":         return .Chest
    case "Boots":         return .Boots
    case "WeaponPrimary": return .WeaponPrimary
    case "WeaponOffhand": return .WeaponOffhand
    case "Consumable":    return .Consumable
    case "Ability1":      return .Ability1
    case "Ability2":      return .Ability2
    case "Ability3":      return .Ability3
    case "Ability4":      return .Ability4
    }
    return .Head
}

@(private = "file")
_parse_rarity :: proc(s: string) -> cw.ItemRarity {
    switch s {
    case "Normal":    return .Normal
    case "Rare":      return .Rare
    case "Epic":      return .Epic
    case "Legendary": return .Legendary
    case "Unique":    return .Unique
    }
    return .Normal
}

@(private = "file")
_parse_rarity_set :: proc(s: string) -> LootRaritySet {
    mask: LootRaritySet
    start := 0
    for i in 0..=len(s) {
        if i == len(s) || s[i] == '|' {
            part := s[start:i]
            if len(part) > 0 { mask |= { _parse_rarity(part) } }
            start = i + 1
        }
    }
    return mask
}

@(private = "file")
_parse_affix_type :: proc(s: string) -> cw.AffixType {
    switch s {
    case "BonusHP":          return .BonusHP
    case "Armor":            return .Armor
    case "BonusMoveSpeed":   return .BonusMoveSpeed
    case "BonusEnergy":      return .BonusEnergy
    case "BonusDamage":      return .BonusDamage
    case "BonusFireRate":    return .BonusFireRate
    case "BonusReloadSpeed": return .BonusReloadSpeed
    case "HealthRegen":      return .HealthRegen
    case "BonusProjSpeed":   return .BonusProjSpeed
    case "BonusPierce":      return .BonusPierce
    case "BonusAmmo":        return .BonusAmmo
    case "BonusMeleeDamage": return .BonusMeleeDamage
    case "BonusMeleeRange":  return .BonusMeleeRange
    case "BonusMeleeSpeed":  return .BonusMeleeSpeed
    case "BonusStrength":    return .BonusStrength
    case "BonusDexterity":   return .BonusDexterity
    case "BonusScience":     return .BonusScience
    case "BonusEnergyRegen": return .BonusEnergyRegen
    case "ReduceEnergyCost": return .ReduceEnergyCost
    case "ResistPhysical":   return .ResistPhysical
    case "ResistNecrotic":   return .ResistNecrotic
    case "ResistFire":       return .ResistFire
    case "ResistGalvanic":   return .ResistGalvanic
    case "ResistPoison":     return .ResistPoison
    }
    return .None
}

@(private = "file")
_parse_weapon_archetype :: proc(s: string) -> cw.WeaponArchetype {
    switch s {
    case "Pistol":  return .Pistol
    case "Rifle":   return .Rifle
    case "Shotgun": return .Shotgun
    case "Axe":     return .Axe
    case "Knife":   return .Knife
    case "Sword":   return .Sword
    }
    return .None
}


@(private = "file")
_parse_affix_list :: proc(s: string, out: []cw.Affix) -> u8 {
    count := 0
    entry_start := 0
    for i in 0..=len(s) {
        if i == len(s) || s[i] == ';' {
            entry := s[entry_start:i]
            entry_start = i + 1
            if len(entry) == 0 { continue }

            colon := -1
            for j in 0..<len(entry) {
                if entry[j] == ':' { colon = j; break }
            }
            if colon < 0 { continue }
            atype := _parse_affix_type(entry[:colon])
            if atype == .None { continue }
            val, ok := strconv.parse_f64(entry[colon+1:])
            if !ok { continue }
            if count >= len(out) { break }
            out[count] = cw.Affix{ type = atype, value = f32(val) }
            count += 1
        }
    }
    return u8(count)
}


spawn_loot_drop :: proc(w: ^cw.World, world_pos: [3]f32, seed: u64, forced_rarity: Maybe(cw.ItemRarity) = nil) {
    if len(g_loot_table) == 0 { return }


    pos: [3]f32 = world_pos
    {
        h := seed ~ (seed >> 30)
        h  = h * 0xbf58476d1ce4e5b9
        h ~= h >> 27
        h  = h * 0x94d049bb133111eb
        h ~= h >> 31
        angle := f32(h & 0xffff) / 65535.0 * 6.2832
        dist  := 6.0 + f32((h >> 16) & 0xffff) / 65535.0 * 18.0
        pos[0] += math.cos(angle) * dist
        pos[1] += math.sin(angle) * dist
    }

    rng_state                := rand.create(seed)
    context.random_generator  = rand.default_random_generator(&rng_state)


    total_weight := 0
    for &d in g_loot_table {
        if d.serum_value == 0 { total_weight += d.roll_weight }
    }
    if total_weight == 0 { return }


    pick := rand.int_max(total_weight)
    acc  := 0
    def: ^LootDef
    for &d in g_loot_table {
        if d.serum_value != 0 { continue }
        acc += d.roll_weight
        if pick < acc { def = &d; break }
    }
    if def == nil { return }

    item_id := cw.world_create_entity(w)
    cw.world_set_transform(w, item_id, cw.TransformComp{ position = pos })

    item_comp := cw.item_empty()
    item_comp.slot               = def.slot
    if fr, ok := forced_rarity.?; ok {
        item_comp.rarity = fr
    } else {
        item_comp.rarity = roll_rarity_allowed(def.rarities)
    }
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
    item_comp.weapon_archetype   = def.weapon_archetype
    item_comp.base_damage        = def.base_damage
    item_comp.base_fire_rate     = def.base_fire_rate
    item_comp.base_ammo_max      = def.base_ammo_max
    item_comp.base_reload_time   = def.base_reload_time
    item_comp.base_proj_speed    = def.base_proj_speed
    item_comp.base_armor         = def.base_armor
    item_comp.base_shield        = def.base_shield

    item_comp.affix_count = def.base_affix_count
    for i in 0..<int(def.base_affix_count) { item_comp.affixes[i] = def.base_affixes[i] }
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


SERUM_DROP_CHANCE :: f32(0.005)


ITEM_DROP_CHANCE_UNIQUE    :: f32(0.0015)
ITEM_DROP_CHANCE_LEGENDARY :: f32(0.0030)
ITEM_DROP_CHANCE_EPIC      :: f32(0.0080)
ITEM_DROP_CHANCE_RARE      :: f32(0.1300)
ITEM_DROP_CHANCE_NORMAL    :: f32(0.6300)

spawn_serum_drop :: proc(w: ^cw.World, world_pos: [3]f32, seed: u64) {
    rng_state                := rand.create(seed)
    context.random_generator  = rand.default_random_generator(&rng_state)


    serum1, serum3: ^LootDef
    for &d in g_loot_table {
        if d.serum_value == 1 && serum1 == nil { serum1 = &d }
        if d.serum_value == 3 && serum3 == nil { serum3 = &d }
    }

    def := serum3 if (serum3 != nil && rand.float32() < 0.25) else serum1
    if def == nil { return }

    item_id := cw.world_create_entity(w)
    cw.world_set_transform(w, item_id, cw.TransformComp{ position = world_pos })

    item_comp              := cw.item_empty()
    item_comp.slot          = def.slot
    item_comp.rarity        = .Epic
    item_comp.serum_value   = def.serum_value
    item_comp.grid_w        = 1
    item_comp.grid_h        = 1
    cw.world_set_item(w, item_id, item_comp)

    rc: cw.RenderConfigComp
    cw.render_config_set_name(&rc, def.name)
    cw.render_config_set_icon(&rc, def.icon)
    cw.render_config_set_desc(&rc, def.desc)
    cw.world_set_render_config(w, item_id, rc)

    cw.world_set_ground_item(w, item_id)
    cw.world_set_fog_of_war(w, item_id)
}


ABILITY_DROP_POOL :: [?]cw.AbilityType{

    .CadavericSpasm, .OsseousSlam, .NecroticSurge, .CrushingGrip,

    .RapidDischarge, .DeliberateRound, .EtherVial, .Indexed,

    .VetriolFlask, .CarbolicSpray, .Contagion, .Exothermic,

    .LaTormenta, .Overcharged, .InductionCoil, .GalvanicShock,
}


ABILITY_DROP_CHANCE :: f32(0.02)


spawn_ability_drop :: proc(w: ^cw.World, world_pos: [3]f32, seed: u64) {
    rng_state                := rand.create(seed)
    context.random_generator  = rand.default_random_generator(&rng_state)
    pool := ABILITY_DROP_POOL
    at   := pool[rand.int_max(len(pool))]
    _spawn_ability_item(w, world_pos, at)
}

@(private = "file")
_spawn_ability_item :: proc(w: ^cw.World, world_pos: [3]f32, at: cw.AbilityType) {
    if at == .None { return }
    if int(at) >= len(ABILITY_DEFS) { return }
    def := ABILITY_DEFS[at]

    item_id := cw.world_create_entity(w)
    cw.world_set_transform(w, item_id, cw.TransformComp{ position = world_pos })

    item               := cw.item_empty()
    item.slot           = .Ability1
    item.ability_type   = at
    item.ability_level  = 1
    item.grid_w         = 1
    item.grid_h         = 1
    item.rarity         = .Epic
    cw.world_set_item(w, item_id, item)

    rc: cw.RenderConfigComp
    cw.render_config_set_name(&rc, def.name)
    cw.render_config_set_icon(&rc, "ability_active")
    cw.render_config_set_desc(&rc, def.desc)
    cw.world_set_render_config(w, item_id, rc)

    cw.world_set_ground_item(w, item_id)
    cw.world_set_fog_of_war(w, item_id)
}


create_ability_item :: proc(w: ^cw.World, at: cw.AbilityType) -> int {
    if at == .None                   { return cw.INVALID_ENTITY }
    if int(at) >= len(ABILITY_DEFS)  { return cw.INVALID_ENTITY }
    def := ABILITY_DEFS[at]

    item_id := cw.world_create_entity(w)
    cw.world_set_transform(w, item_id, cw.TransformComp{})

    item              := cw.item_empty()
    item.slot          = .Ability1
    item.ability_type  = at
    item.ability_level = 1
    item.grid_w        = 1
    item.grid_h        = 1
    item.rarity        = .Epic
    cw.world_set_item(w, item_id, item)

    rc: cw.RenderConfigComp
    cw.render_config_set_name(&rc, def.name)
    cw.render_config_set_icon(&rc, "ability_active")
    cw.render_config_set_desc(&rc, def.desc)
    cw.world_set_render_config(w, item_id, rc)

    return item_id
}

give_class_starter_items :: proc(w: ^cw.World, pid: int, class_idx: int) {
    ci := clamp(class_idx, 0, 3)

    // Ensure the visual reflects the chosen class immediately.
    // get_entity_sprite_stem() returns g_player_stem directly, so this
    // must be set before spawn_players sets the RenderConfig sprite key.
    stems := PLAYER_STEMS
    g_player_stem = stems[ci]
    g_selected_class_idx = ci

    if cw.world_has_component(w, pid, .Stats) {
        st            := cw.world_get_stats(w, pid)
        st.strength    = CLASS_BASE_STR[ci]
        st.dexterity   = CLASS_BASE_DEX[ci]
        st.science     = CLASS_BASE_SCI[ci]
        st.base_hp     = CLASS_BASE_HP[ci]
        st.base_energy = CLASS_BASE_ENERGY[ci]
        st.base_speed  = CLASS_BASE_SPEED[ci]
    }

    if cw.world_has_component(w, pid, .Health) {
        h            := cw.world_get_health(w, pid)
        h.max         = CLASS_BASE_HP[ci]
        h.current     = CLASS_BASE_HP[ci]
        h.max_energy  = CLASS_BASE_ENERGY[ci]
        h.energy      = CLASS_BASE_ENERGY[ci]
    }

    give_starter_items(w, pid)

    switch ci {
    case 1:
        _give_class_weapon(w, pid, .Shotgun, cw.Affix{})
    case 2:
        _give_class_weapon(w, pid, .Pistol, cw.Affix{type = .BonusFireRate, value = 0.30})
    }

    at    := CLASS_STARTER_ABILITIES[ci]
    ab_id := create_ability_item(w, at)
    if cw.world_is_valid(w, ab_id) && cw.world_has_component(w, pid, .Inventory) {
        inv := cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.Ability1)] = ab_id
    }
}

@(private = "file")
_give_class_weapon :: proc(w: ^cw.World, pid: int, archetype: cw.WeaponArchetype, extra_affix: cw.Affix) {
    if !cw.world_has_component(w, pid, .Inventory) { return }

    inv     := cw.world_get_inventory(w, pid)
    old_wep := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
    if cw.world_is_valid(w, old_wep) {
        cw.world_destroy_entity(w, old_wep)
        inv = cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.WeaponPrimary)] = cw.INVALID_ENTITY
    }

    for &d in g_loot_table {
        if d.slot != .WeaponPrimary        { continue }
        if d.weapon_archetype != archetype { continue }
        if .Normal not_in d.rarities       { continue }

        wep_id := cw.world_create_entity(w)
        if !cw.world_is_valid(w, wep_id) { break }

        item_comp                 := cw.item_empty()
        item_comp.slot             = .WeaponPrimary
        item_comp.rarity           = .Normal
        item_comp.grid_w           = d.grid_w
        item_comp.grid_h           = d.grid_h
        item_comp.req_str          = d.req_str
        item_comp.req_dex          = d.req_dex
        item_comp.req_sci          = d.req_sci
        item_comp.is_two_handed    = d.is_two_handed
        item_comp.is_melee         = d.is_melee
        item_comp.weapon_archetype = d.weapon_archetype
        item_comp.base_damage      = d.base_damage
        item_comp.base_fire_rate   = d.base_fire_rate
        item_comp.base_ammo_max    = d.base_ammo_max
        item_comp.base_reload_time = d.base_reload_time
        item_comp.base_proj_speed  = d.base_proj_speed
        item_comp.base_armor       = d.base_armor
        item_comp.base_shield      = d.base_shield
        item_comp.affix_count      = d.base_affix_count
        for i in 0..<int(d.base_affix_count) { item_comp.affixes[i] = d.base_affixes[i] }

        if extra_affix.type != .None {
            idx := int(item_comp.affix_count)
            if idx < cw.MAX_AFFIXES {
                item_comp.affixes[idx]  = extra_affix
                item_comp.affix_count  += 1
            }
        }

        roll_affixes(&item_comp)
        cw.world_set_item(w, wep_id, item_comp)

        rc: cw.RenderConfigComp
        cw.render_config_set_name(&rc, d.name)
        cw.render_config_set_icon(&rc, d.icon)
        cw.render_config_set_desc(&rc, d.desc)
        cw.world_set_render_config(w, wep_id, rc)

        inv = cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.WeaponPrimary)] = wep_id
        break
    }
}

loot_seed :: proc(tick: u64, entity_id: int) -> u64 {
    h := (u64(entity_id) + 1) * 6364136223846793005 ~ (tick * 2685821657736338717)
    h ~= h >> 33
    h  *= 0xff51afd7ed558ccd
    h ~= h >> 33
    return h
}


give_starter_items :: proc(w: ^cw.World, pid: int) {
    if !cw.world_has_component(w, pid, .Inventory) { return }
    inv := cw.world_get_inventory(w, pid)


    hf_id := create_flask_item(w, .Health, .Small, .Normal)
    if cw.world_is_valid(w, hf_id) {
        inv = cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.Flask1)] = hf_id
    }


    ef_id := create_flask_item(w, .Energy, .Small, .Normal)
    if cw.world_is_valid(w, ef_id) {
        inv = cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.Flask2)] = ef_id
    }


    for &d in g_loot_table {
        if d.slot != .WeaponPrimary          { continue }
        if d.weapon_archetype != .Pistol     { continue }
        if .Normal not_in d.rarities         { continue }

        wep_id := cw.world_create_entity(w)
        if !cw.world_is_valid(w, wep_id)    { break }

        item_comp                  := cw.item_empty()
        item_comp.slot              = .WeaponPrimary
        item_comp.rarity            = .Normal
        item_comp.grid_w            = d.grid_w
        item_comp.grid_h            = d.grid_h
        item_comp.req_str           = d.req_str
        item_comp.req_dex           = d.req_dex
        item_comp.req_sci           = d.req_sci
        item_comp.is_two_handed     = d.is_two_handed
        item_comp.is_melee          = d.is_melee
        item_comp.weapon_archetype  = d.weapon_archetype
        item_comp.base_damage       = d.base_damage
        item_comp.base_fire_rate    = d.base_fire_rate
        item_comp.base_ammo_max     = d.base_ammo_max
        item_comp.base_reload_time  = d.base_reload_time
        item_comp.base_proj_speed   = d.base_proj_speed
        item_comp.base_armor        = d.base_armor
        item_comp.base_shield       = d.base_shield
        item_comp.affix_count       = d.base_affix_count
        for i in 0..<int(d.base_affix_count) { item_comp.affixes[i] = d.base_affixes[i] }
        roll_affixes(&item_comp)
        cw.world_set_item(w, wep_id, item_comp)

        rc: cw.RenderConfigComp
        cw.render_config_set_name(&rc, d.name)
        cw.render_config_set_icon(&rc, d.icon)
        cw.render_config_set_desc(&rc, d.desc)
        cw.world_set_render_config(w, wep_id, rc)

        inv = cw.world_get_inventory(w, pid)
        inv.equipped[int(cw.EquipSlot.WeaponPrimary)] = wep_id
        break
    }
}

