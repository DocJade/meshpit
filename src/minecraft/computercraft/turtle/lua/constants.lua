-- This file contains constants that are never changed during the runtime of the
-- turtle.
local constants = {}

--- Movement vectors based on cardinal directions, including up and down.
---@type {[string]: CoordPosition}
constants.movement_vectors = {
    n = {
        x = 0,
        y = 0,
        z = -1
    },
    e = {
        x = 1,
        y = 0,
        z = 0
    },
    s = {
        x = 0,
        y = 0,
        z = 1
    },
    w = {
        x = -1,
        y = 0,
        z = 0
    },
    u = {
        x = 0,
        y = 1,
        z = 0
    },
    d = {
        x = 0,
        y = -1,
        z = 0
    },
}

--- Integer representations of cardinal directions. 1 indexed, clockwise from north.
---@type string[]
constants.dirs = {"n", "e", "s", "w"}

--- Allow converting from string forms of cardinal directions to their one indexed
--- counterpart in `dirs`
---@type {[CardinalDirection]: number}
constants.dir_to_num = {n = 1, e = 2, s = 3, w = 4}

--- How long debugging wait_step() calls should wait before timing out.
---
--- This is in seconds, but unfortunately this refers to _ingame_ seconds, but
--- since we aren't doing the time deltas ourselves and cannot provide timestamps
--- instead of raw second durations, if the game is tick sprinting, this will
--- time out VERY fast. Thus... its a really big value.
--- assuming we can sprint at 50,000TPS (about 50% faster than I have been able to
--- run the server at doing nothing), this would be 5 minutes
---@type number
constants.WAIT_STEP_TIMEOUT = 15000000 -- 15,000,000

--- Blocks that the turtle can always move into besides air.
---
--- Things that you think you might be able to move through but cant:
--- - kelp
--- - skulk_vein
---
--- A list of full names.
--- @type string[]
constants.OCCUPIABLE_BLOCKS = {
    "minecraft:water",
    "minecraft:lava",
    "minecraft:short_grass",
    "minecraft:tall_grass",
    "minecraft:fern",
    "minecraft:large_fern",
    "minecraft:dead_bush",
    "minecraft:crimson_roots",
    "minecraft:warped_roots",
    "minecraft:nether_sprouts",
    "minecraft:glow_lichen",
    "minecraft:hanging_roots",
    "minecraft:vines",
    "minecraft:sea_grass",
}

--- Blocks that cannot be mined safely and require the `unsafe` flag to be set
--- on the dig operation.
---
--- A list of full names.
--- @type string[]
constants.UNSAFE_BLOCKS = {
    "computercraft:turtle_normal",
    "computercraft:turtle_advanced",
    "computercraft:disk_drive",
}

return constants