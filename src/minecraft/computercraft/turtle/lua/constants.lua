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

return constants