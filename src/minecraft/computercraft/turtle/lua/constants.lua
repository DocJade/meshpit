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
---@type number
constants.WAIT_STEP_TIMEOUT = 240

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

return constants