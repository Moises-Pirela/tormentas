package clockwork

CHUNK_SIZE     :: 256
MAX_COMPONENTS :: 128
MAX_PEERS      :: #config(CW_MAX_PEERS, 8)

EntityId :: int

INVALID_ENTITY :: EntityId(-1)

ComponentId :: distinct u8

PeerId :: int

INVALID_PEER :: PeerId(-1)
