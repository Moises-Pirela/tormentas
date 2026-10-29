#!/usr/bin/env python3
import struct
from pathlib import Path

FLOOR = 1
WALL  = 2

OVERLAY_OIL  = 1
OVERLAY_FIRE = 2

CHEST   = 0
CRATE   = 1
LOCKER  = 2
CABINET = 3

def rect(x0, y0, x1, y1):
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}

def make_label(s: str) -> bytes:
    b = s.encode("utf-8")[:23]
    return b + bytes(24 - len(b))

def wb1(v):   return struct.pack("<B",  int(v) & 0xFF)
def wb2(v):   return struct.pack("<H",  int(v) & 0xFFFF)
def wb4(v):   return struct.pack("<I",  int(v) & 0xFFFFFFFF)
def wbi16(v): return struct.pack("<h",  int(v))
def wbf32(v): return struct.pack("<f",  float(v))

TILE_SIZE = 40

floor_tiles: set = set()

floor_tiles |= rect(-13, -4, -6, 4)

floor_tiles |= rect(-5, -1, -3, 1)

floor_tiles |= rect(-2, -5, 6, 4)

floor_tiles |= rect(0, -7, 4, -6)

floor_tiles |= rect(7, -1, 8,  1)

floor_tiles |= rect(7, -5, 14, 3)

floor_tiles |= rect(-1, 5, 5, 8)

floor_tiles |= rect(9, 4, 13, 7)

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

spawns = []

exits = []

player_start_x = float(0 * TILE_SIZE + TILE_SIZE // 2)
player_start_y = float(0 * TILE_SIZE + TILE_SIZE // 2)

npcs = []

lights = [
    ( -9,  0,   70, 120, 240, 240, 0.95),
    (-12, -3,  255, 175,  75, 130, 0.65),
    ( -7, -3,  255, 155,  55, 110, 0.60),
    ( -7,  3,  255, 155,  55, 110, 0.55),

    ( -4,  0,  255, 140,  50,  95, 0.55),

    (  1,  0,  255, 215, 125, 260, 0.95),
    (  5, -4,  255, 170,  70, 140, 0.70),
    ( -1, -4,  255, 160,  60, 130, 0.65),
    (  5,  3,  255, 165,  65, 130, 0.60),
    ( -1,  3,  255, 155,  55, 120, 0.58),

    (  2, -6,  255, 145,  50, 120, 0.62),

    ( 10,  0,  255, 205, 100, 210, 0.90),
    ( 13, -4,  255, 165,  55, 150, 0.72),
    (  8, -4,  255, 145,  45, 130, 0.65),
    ( 13,  2,  255, 160,  60, 130, 0.62),

    (  2,  6,  255, 155,  45, 180, 0.78),
    (  4,  7,  255, 130,  30, 120, 0.55),

    ( 11,  5,  255, 150,  55, 140, 0.65),
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
    80.0,
    1.35,
    22.0,
    18.0,
    12.0,
    130.0,
    82.0,
    0.60,
    0.55,
    0.28,
    0.62,
    0.68,
    255.0,
    225.0,
    175.0,
    0.52,
    1.60,
    0.65,
    0.40,
    0.52,
    22.0,
    17.0,
    12.0,
    0.36,
    1.45,
]

assert len(lighting_cfg) == 35, f"Expected 35 lighting values, got {len(lighting_cfg)}"

barrels = [
    (-11, -1, 1),
    (  0,  3, 1),
    ( 13,  1, 1),
    (  4,  7, 1),
]

overlays = []

doors    = []
switches = []

containers = [
    (-12, -3, CRATE,   0,  4, 12),
    ( -6,  3, CRATE,   0,  3, 10),

    ( -1, -4, LOCKER,  0, 10, 25),
    (  5, -4, CRATE,   0,  5, 15),
    (  5,  3, CRATE,   0,  4, 12),

    (  1, -6, CABINET, 0, 20, 45),
    (  3, -6, CRATE,   0,  5, 15),

    ( 14, -4, LOCKER,  0, 10, 22),
    ( 14,  2, CRATE,   0,  4, 12),

    (  4,  7, CABINET, 0,  8, 20),
    ( -1,  7, CRATE,   0,  3,  8),

    ( 13,  6, CRATE,   0,  5, 15),
    (  9,  6, LOCKER,  0, 10, 22),
]

lore_items  = []
phonographs = []
key_pickups = []

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

buf += wb4(len(doors))

buf += wb4(len(switches))

buf += wb4(len(containers))
for (x, y, kind, loot_id, gmin, gmax) in containers:
    buf += wbi16(x)
    buf += wbi16(y)
    buf += wb1(kind)
    buf += wb1(loot_id)
    buf += wb2(gmin)
    buf += wb2(gmax)

buf += wb4(len(lore_items))

buf += wb4(len(phonographs))

buf += wb4(len(key_pickups))

out_path = Path(__file__).parent.parent / "data" / "levels" / "level00.bin"
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_bytes(buf)

n_floor = len(floor_tiles)
n_wall  = len(wall_tiles)
print(f"Written {len(buf):,} bytes to {out_path}")
print(f"  Tiles:      {len(tiles):4d}  ({n_floor} floor + {n_wall} wall)")
print(f"  Spawns:     {len(spawns):4d}  (none — safe zone)")
print(f"  Exits:      {len(exits):4d}  (none — hub)")
print(f"  Lights:     {len(lights):4d}")
print(f"  Barrels:    {len(barrels):4d}")
print(f"  Containers: {len(containers):4d}")
print(f"  Player start: ({player_start_x:.0f}, {player_start_y:.0f})  [tile 0,0]")
print()

import math
anchors = [
    ("Portal",      -300,   0),
    ("Shopkeeper",   200,   0),
    ("Workbench",    300, -40),
    ("Stash",        105, -95),
    ("Player",         0,   0),
]
print("NPC anchor verification:")
for name, wx, wy in anchors:
    tx = math.floor(wx / TILE_SIZE)
    ty = math.floor(wy / TILE_SIZE)
    ok = (tx, ty) in floor_tiles
    status = "OK floor" if ok else "!! WALL/MISSING !!"
    print(f"  {name:12s}  world ({wx:5},{wy:4})  tile ({tx:3},{ty:3})  {status}")
