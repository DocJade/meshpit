-- Fly into the sky to determine our Y level.

local task_helpers = require("task_helpers")

--- The configuration for the height normalization task.
---
--- This task flies straight up into the air until it hits Y level 319, then
--- flies back down till it touches the ground again in order to calibrate the
--- Y level of walkback using the height limit as reference.
---
--- This is really only meant to be called once ever by the first turtle ever
--- added to the swarm
---
--- !!! THIS RESETS WALKBACK ONCE LANDED !!!
---
--- Assumptions this task makes:
--- - The turtle has a direct view of the sky
--- - The turtle has at least 800 fuel.
---
--- Task completion states:
--- - Turtle flew up, then down.
---
--- Task failure states:
--- - Turtle somehow ran out of fuel during flight
--- - Hit a block on the way up
---
--- Notes:
--- - No timeout.
--- - Returns NoneResult since it just updates the walkback internals.
--- @class NormalizeHeightData
--- @field name "normalize_height"


--- FLy up to 319 and back down to set walkback's vertical position.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function normalizeHeight(config)
    local wb = config.walkback

    -- Right task?
    if config.definition.task_data.name ~= "normalize_height" then
        task_helpers.throw("bad config")
    end

    -- Enough fuel?
    if wb:getFuelLevel() < 800 then
        task_helpers.throw("bad config")
    end

    -- its fly time
    while true do
        local moved, reason = wb:up()

        if moved then
            --  Keep going, not there yet
        elseif reason == "Too high to move" then
            -- Hit the top!
            wb.cur_position.position.y = 319
            break

        elseif reason == "Out of fuel" then
            -- ... how?
            task_helpers.throw("out of fuel")
        else
            -- Anything else, something in the way, idk.
            task_helpers.throw("assumptions not met")
        end
    end

    -- "Icarus laughed as he fell,"
    while true do
        task_helpers.taskYield()

        local moved, reason = wb:down()

        if moved then
            -- "for he knew to fall means to once have soared"

        elseif reason == "Movement obstructed" then
            -- Splat
            break
        elseif reason == "Out of fuel" then
            -- Once again, idk how this could ever happen
            task_helpers.throw("out of fuel")

        else
            -- Idk man.
            task_helpers.throw("assumptions not met")
        end
    end

    -- Nuke Walkback as we have now probably messed up the chain irreconcilably,
    -- and all of the relative positioning is now incorrect.
    wb:hardReset()
    wb:mark()

    ---@type NoneResult
    local result = { name = "none" }
    return task_helpers.tryFinishTask(config, result)
end

return normalizeHeight