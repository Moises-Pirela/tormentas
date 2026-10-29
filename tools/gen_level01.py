#!/usr/bin/env python3
import struct
from pathlib import Path

FLOOR = 1
WALL  = 2

OVERLAY_OIL  = 1
OVERLAY_FIRE = 2

MELEE  = 1
BRUTE  = 2
HUNTER = 3
RANGED = 4
SNIPER = 5

CHEST   = 0
CRATE   = 1
LOCKER  = 2
CABINET = 3

DOOR_NONE  = 0
DOOR_LEVER = 1
DOOR_KEY   = 2

def rect(x0, y0, x1, y1):
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}

def make_label(s: str) -> bytes:
    b = s.encode("utf-8")[:23]
    return b + bytes(24 - len(b))

def wb1(v):  return struct.pack("<B", int(v) & 0xFF)
def wb2(v):  return struct.pack("<H", int(v) & 0xFFFF)
def wb4(v):  return struct.pack("<I", int(v) & 0xFFFFFFFF)
def wbi16(v): return struct.pack("<h", int(v))
def wbf32(v): return struct.pack("<f", float(v))

floor_tiles: set = set()
floor_tiles |= rect(2,  2,  7,  5)
floor_tiles |= rect(8,  3, 11,  4)
floor_tiles |= rect(12, 1, 23,  9)
floor_tiles |= rect(24, 2, 28,  5)
floor_tiles |= rect(29, 1, 38,  9)
floor_tiles |= rect(16,10, 19, 14)
floor_tiles |= rect(12,15, 22, 22)
floor_tiles |= rect(16,23, 17, 27)
floor_tiles |= rect(13,28, 20, 36)

wall_tiles: set = set()
for (fx, fy) in floor_tiles:
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nb = (fx + dx, fy + dy)
            if nb not in floor_tiles:
                wall_tiles.add(nb)

tiles = [(x, y, FLOOR) for (x, y) in floor_tiles] + \
        [(x, y, WALL)  for (x, y) in wall_tiles]

spawns = [
    ( 3,  3, MELEE),
    ( 6,  4, HUNTER),

    (13,  2, MELEE),
    (16,  5, RANGED),
    (22,  3, MELEE),
    (21,  7, BRUTE),

    (30,  2, MELEE),
    (34,  5, BRUTE),
    (37,  3, RANGED),
    (38,  8, SNIPER),

    (13, 16, HUNTER),
    (20, 17, MELEE),
    (17, 20, BRUTE),

    (15, 29, HUNTER),
    (19, 34, SNIPER),
]

exits = [
    ( 7,  5, 0),
    (23,  9, 0),
    (17, 35, 0),
]

TILE_SIZE = 40
player_start_x = float(4 * TILE_SIZE + TILE_SIZE // 2)
player_start_y = float(3 * TILE_SIZE + TILE_SIZE // 2)

npcs = []

lights = [
    ( 4,  3, 255, 180,  80, 160.0, 0.80),
    ( 7,  4, 255, 160,  60, 110.0, 0.70),
    (17,  5, 255, 200, 100, 200.0, 0.75),
    (23,  2, 255, 170,  70, 130.0, 0.65),
    (12,  9, 220, 155,  55, 120.0, 0.60),
    (33,  4, 255, 165,  60, 180.0, 0.80),
    (38,  8, 210, 140,  50, 110.0, 0.65),
    (17, 18, 255, 100,  20, 170.0, 0.95),
    (17, 35,  80, 105, 210, 190.0, 0.80),
]

lighting_cfg = [
    0.84,
    0.54,
    0.0032,
    0.0075,
    12.0,
    6.5,
    28.0,
    0.42,
    0.68,
    30.0,
    124.0,
    1.35,
    18.0,
    30.0,
    14.0,
    130.0,
    82.0,
    0.60,
    1.0,
    0.18,
    0.35,
    0.90,
    244.0,
    228.0,
    184.0,
    0.35,
    1.80,
    0.70,
    0.45,
    0.65,
    6.0,
    4.0,
    8.0,
    0.72,
    1.80,
]

assert len(lighting_cfg) == 35, f"Expected 35 lighting values, got {len(lighting_cfg)}"

barrels = [
    (17, 19, 0),
    (13, 16, 1),
]

overlays = [
    (15, 18, OVERLAY_OIL),
    (16, 18, OVERLAY_OIL),
    (16, 19, OVERLAY_OIL),
    (17, 18, OVERLAY_OIL),
    (18, 19, OVERLAY_OIL),
    (18, 20, OVERLAY_OIL),
]

doors = [
    (16, 24, 0, 2, DOOR_KEY, True, "Vault Key Required"),
]

switches = []

containers = [
    ( 2,  2, CRATE,    0,   5,  15),

    (12,  1, LOCKER,   0,   5,  20),
    (23,  1, CHEST,    1,  10,  35),
    (12,  9, CRATE,    0,   2,  10),

    (29,  1, LOCKER,   0,   5,  20),
    (38,  1, CHEST,    1,  15,  45),
    (29,  8, CABINET,  0,   5,  15),

    (12, 15, CRATE,    0,   5,  20),
    (22, 22, CRATE,    0,   3,  12),

    (13, 28, CHEST,    2,  80, 250),
    (20, 36, CABINET,  0,  20,  50),
]

lore_items  = []
phonographs = []

key_pickups = [
    (37, 7, 2),
]

buf = bytearray()

buf += b"TRMT"
buf += wb2(9)

buf += wb4(len(tiles))
for (x, y, tt) in tiles:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(tt)

buf += wb4(len(spawns))
for (x, y, et) in spawns:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(et)

buf += wb4(len(exits))
for (x, y, tl) in exits:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb2(tl)

buf += wbf32(player_start_x)
buf += wbf32(player_start_y)

buf += wb4(len(npcs))
for (x, y, nt) in npcs:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(nt)

buf += wb4(len(lights))
for (x, y, r, g, b, radius, intensity) in lights:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(r)
    buf += wb1(g)
    buf += wb1(b)
    buf += wbf32(radius)
    buf += wbf32(intensity)

for v in lighting_cfg:
    buf += wbf32(v)

buf += wb4(len(barrels))
for (x, y, bt) in barrels:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(bt)

buf += wb4(len(overlays))
for (x, y, ov) in overlays:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(ov)

buf += wb4(len(doors))
for (x, y, link_id, key_id, open_type, is_locked, label_str) in doors:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(link_id)
    buf += wb1(key_id)
    buf += wb1(open_type)
    buf += wb1(1 if is_locked else 0)
    buf += make_label(label_str)

buf += wb4(len(switches))
for (x, y, li, fl) in switches:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(li)
    buf += wb1(fl)

buf += wb4(len(containers))
for (x, y, kind, loot_id, gmin, gmax) in containers:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(kind)
    buf += wb1(loot_id)
    buf += wb2(gmin)
    buf += wb2(gmax)

buf += wb4(len(lore_items))
for (x, y, lid) in lore_items:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(lid)

buf += wb4(len(phonographs))
for (x, y, rid) in phonographs:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(rid)

buf += wb4(len(key_pickups))
for (x, y, ki) in key_pickups:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(ki)

out_path = Path(__file__).parent.parent / "data" / "levels" / "level01.bin"
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_bytes(buf)

print(f"Written {len(buf):,} bytes to {out_path}")
print(f"  Tiles:      {len(tiles):4d}  ({len(floor_tiles)} floor + {len(wall_tiles)} wall)")
print(f"  Spawns:     {len(spawns):4d}")
print(f"  Exits:      {len(exits):4d}  (all are timed extraction zones)")
print(f"  Lights:     {len(lights):4d}")
print(f"  Barrels:    {len(barrels):4d}")
print(f"  Overlays:   {len(overlays):4d}")
print(f"  Doors:      {len(doors):4d}")
print(f"  Containers: {len(containers):4d}  (loot_table 0:{sum(1 for c in containers if c[3]==0)}  1:{sum(1 for c in containers if c[3]==1)}  2:{sum(1 for c in containers if c[3]==2)})")
print(f"  Key pickups:{len(key_pickups):4d}")
print(f"  Player start: ({player_start_x:.0f}, {player_start_y:.0f})  [tile 4,3]")
