-- Chops down trees!

--- Assumptions this task makes:
--- - The turtle is equipped with a tool that can break logs and leaves.
--- - The task is started in one of the following conditions:
--- - - Turtle is facing the base block of a tree.
--- - - Turtle is facing a sapling, and needs to wait for it to grow.
--- - - The turtle is facing an empty tree-growable block, and has a sapling it can place.
--- - The task either starts with at least 100 fuel.
--- - There is at least one empty inventory slot for the logs to go into
---
--- Task completion states:
--- - The task has been running for longer than the alloted time.
--- - The requested amount of logs has been gathered.
--- - The turtle is not allowed to refuel on its own logs, and doesn't have
---   enough fuel to continue.
---
--- Task failures states:
--- - The turtle runs out of saplings and is unable to continue chopping.
--- - - The turtle will collect its own saplings while chopping, but there is
---     always a chance there just won't be a new sapling from the tree. This
---     should be relatively rare.
--- - The inventory of the turtle can't hold any more items.
---

--- Tree facts:
--- - Trees take on average ~1000 seconds to grow (https://www.minecraftforum.net/forums/minecraft-java-edition/discussion/2937790-tree-growth-rate)
--- -

--- The configuration for this task.
--- @class TreeChopTaskData
--- @field name "tree_chop"
--- @field timeout number -- Maximum number of seconds to spend in this task.
--- @field target_logs number? -- Target number of logs to have in the inventory before stopping. Will harvest until time limit is hit if not set. Does not include logs already in the inventory when the task was started.
--- @field target_saplings number? -- Target number of saplings to keep on hand. Extras will be burnt as fuel. Defaults to 16.
--- @field self_refuel boolean -- Is the turtle allowed to fuel itself with the logs it harvests to keep going?

local helpers = require "helpers"
local task_helpers = require "task_helpers"
local sapling_tag = "minecraft:saplings"
local log_tag = "minecraft:logs"
local leaves_tag = "minecraft:leaves"

--- Task that automatically cuts down trees.
---
--- Takes in a task config. see TreeChopTaskData for the sub-config.
---@param config TaskConfig
---@return TaskCompletion|TaskFailure
local function tree_chop(config)
    local wb = config.walkback
    -- Make sure the task name is correct
    if config.task_data.name ~= "tree_chop" then
        -- Wrong task.
        task_helpers.throw("bad config")
    end

    -- Task must start with more fuel than the buffer amount.
    if config.fuel_buffer > wb.getFuelLevel() then
        task_helpers.throw("out of fuel")
    end

    -- Start timestamp must be in the past
    ---@diagnostic disable-next-line: undefined-field
    if config.start_time > os.epoch("utc") then
        -- Task starts in the future.
        task_helpers.throw("bad config")
    end

    -- There should be no previous steps in the walkback
    if wb.previousPosition ~= nil then
        -- Walkback already had data in it.
        task_helpers.throw("bad config")
    end



    -- Check assumptions

    -- We can assume we have a tool, if breaking fails due to not having a tool,
    -- we will return there.

    -- Facing log or sapling
    local check_block = wb.inspect()
    if not check_block then
        -- Can't possibly be a log or sapling.
        goto sapling_check
    end

    local facing_sapling = helpers.arrayContains(check_block.tag, sapling_tag)
    local facing_log = helpers.arrayContains(check_block.tag, log_tag)

    -- Find if we have saplings, and what the highest empty slot is.
    ::sapling_check::

    -- Pre-sort the inventory to make room at the front.
    task_helpers.pushInventoryBack(wb)

    local have_sapling = false
    local sapling_slot = 1000
    local highest_empty = 0
    local empty_slots = 0
    for i = 1, 16 do
        local slot = wb.getItemDetail(i, true)
        if slot then
            if helpers.arrayContains(slot.tags, "minecraft:saplings") then
                have_sapling = true
                sapling_slot = math.min(i, sapling_slot)
                break
            end
        else
            highest_empty = math.max(i, highest_empty)
            empty_slots = empty_slots + 1
        end
    end

    -- If there are no empty slots for both the logs and saplings ( if
    -- we dont have some already ) we cannot continue, as our inventory would be full.
    if empty_slots == 0 or (empty_slots <= 1 and sapling_slot == 1000) then
        task_helpers.throw("assumptions not met")
    end

    -- Pull the saplings into slot 1 if it exists
    if sapling_slot ~= 1000 then
        -- Slot should be empty.
        task_helpers.assert(wb.transferFromSlotTo(sapling_slot, 1))
        sapling_slot = 1

        -- Fix the gap that made
        ---@type boolean[]
        local reserved_slot = {}
        reserved_slot[1] = true
        task_helpers.pushInventoryBack(wb, reserved_slot)

        -- Select the sapling
        wb.select(1)
    end

    -- If there is already a sapling or log we can skip placement
    if (facing_log or false) or (facing_sapling or false) then
        goto assumptions_met
    end

    -- There wasn't a sapling or log, was it empty?
    if not check_block then
        -- Invalid position, non-tree block in front of turtle.
        task_helpers.throw("assumptions not met")
    end

    -- We need to place a sapling. If we don't have any, we cannot continue.
    if sapling_slot == 1000 then
        task_helpers.throw("assumptions not met")
    end

    -- Check the block where we would be placing the sapling. It must be some kind of dirt.
    -- ^^^ This check will no longer work in Minecraft 26.1
    -- We already checked that the block in front of us is air
    task_helpers.assert(wb.forward())
    local down_block = wb.inspectDown()
    if have_sapling and down_block ~= nil then
        if helpers.arrayContains(down_block.tag, "minecraft:dirt") then
            task_helpers.assert(wb.stepBack())
            -- Place the sapling
            task_helpers.assert(wb.place())
            goto assumptions_met
        end
    end


    -- If we made it here, we missed the assumptions we needed.
    -- IE, we have:
    -- - No log
    -- - No placed sapling
    -- - No sapling item with a valid placing location
    -- - No bitches
    task_helpers.throw("assumptions not met")

    ::assumptions_met::

    -- Start the loop!
    while true do
        -- Do we still have time?
        local current_time = os.epoch("utc")
        if current_time - config.start_time > config.task_data.timeout * 1000 then
            -- Out of time!
            return task_helpers.try_finish_task(config)
        end
    end

    -- TODO: actual task
    return

end

return tree_chop