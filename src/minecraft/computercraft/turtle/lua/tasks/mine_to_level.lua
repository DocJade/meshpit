-- Task that just digs straight up or down until it hits a certain Y level.
-- This is gross due to boring random holes in the world but we can do something
-- nicer later.


local task_helpers = require("task_helpers")
local helpers = require("helpers")

--- The configuration for the mine down task.
---
--- This task mines a hole straight downwards until a desired Y level is reached.
---
--- Please get rid of this some day. This task also doesn't discard anything it mines
---
--- Assumptions this task makes:
--- - The turtle has a tool to dig with
--- - The turtle has enough fuel to mine down to the requested level
--- - You dont gaf about the landscape
---
--- Task completion states:
--- - Turtle mined to the level requested.
---
--- Task failure states:
--- - Not enough fuel
--- - Unbreakable / unsafe block hit on the way.
--- - Inventory full.
---
--- Notes:
--- - No timeout.
--- - Returns NoneResult since it just mines to that level
--- @class MineToLevelData
--- @field name "mine_to_level"
--- @field level number -- The desired Y level.


--- Mine through the world till a desired Y level is hit.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function mineToLevel(config)
    local wb = config.walkback
    local task_data = config.definition.task_data
    -- Right task?
    if config.definition.task_data.name ~= "mine_to_level" then
        task_helpers.throw("bad config")
    end
    --- @cast task_data MineToLevelData
    local level = task_data.level


    -- Enough fuel?
    if wb:getFuelLevel() < math.abs(wb.cur_position.position.y - level) then
        task_helpers.throw("bad config")
    end

    -- Need to have inventory space.
    if wb:countEmptySlots() == 0 then
        task_helpers.throw("assumptions not met")
    end

    -- Dig.
    -- Move up or down automagically.
    local fails = 0
    while true do
        if wb.cur_position.position.y == level then break end
        if fails >= 10 then
            task_helpers.throw("assumptions not met")
        end

        local new_pos = helpers.clonePosition(wb.cur_position.position)

        if level > wb.cur_position.position.y then
            new_pos.y = new_pos.y + 1
        else
            new_pos.y = new_pos.y - 1
        end

        local bool, result = wb:digAdjacent(new_pos)
        if not bool and result ~= "Nothing to dig here" then
            task_helpers.throw("assumptions not met")
        end

        ---@diagnostic disable-next-line: redefined-local
        local bool, result = wb:moveAdjacent(new_pos)
        if not bool then
            -- Could be some bs with sand, cant be assed rn. just try again a few times
            fails = fails + 1
        else
            fails = 0
        end
    end

    -- Hit da level

    ---@type NoneResult
    local result = { name = "none" }
    return task_helpers.tryFinishTask(config, result)
end

return mineToLevel