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

--- The configuration for the tree_chop task.
--- @class TreeChopTaskData
--- @field name "tree_chop"
--- @field timeout number -- Maximum number of seconds to spend in this task.
--- @field target_logs number? -- Target number of logs to have in the inventory before stopping. Will harvest until time limit is hit if not set. Does not include logs already in the inventory when the task was started.
--- @field target_saplings number? -- Target number of saplings to keep on hand. Extras will be burnt as fuel. Defaults to 16.

local helpers = require "helpers"
local task_helpers = require "task_helpers"
local sapling_tag = "minecraft:saplings"
local log_tag = "minecraft:logs"
local leaves_tag = "minecraft:leaves"

--- Task that automatically cuts down trees.
---
--- May leave a lingering tree or sapling.
---
--- Will use logs harvested to refuel itself to continue the task.
---
--- Takes in a TurtleTask. see TreeChopTaskData for the sub-config.
---@param config TurtleTask
---@return TaskCompletion|TaskFailure
local function tree_chop(config)
    print("[Tree chop] : Starting tree chop")
    local wb = config.walkback
    -- Make sure the task name is correct
    if config.definition.task_data.name ~= "tree_chop" then
        -- Wrong task.
        task_helpers.throw("bad config")
    end
    print("[Tree chop] : Good name")

    -- we now know that this is a tree_chop task
    local task_data = config.definition.task_data
    ---@cast task_data TreeChopTaskData

    -- Task must start with more fuel than the buffer amount.
    if config.definition.fuel_buffer > wb:getFuelLevel() then
        task_helpers.throw("out of fuel")
    end
    print("[Tree chop] : Good fuel")

    -- There should be no previous steps in the walkback
    if wb:previousPosition() ~= nil then
        -- Walkback already had data in it.
        task_helpers.throw("bad config")
    end
    print("[Tree chop] : Good walkback")

    -- Pre-create all of the locals so goto isnt mad.
    -- TODO: this is stupid
    local check_block
    local facing_sapling
    local facing_log
    local sapling_slot
    local empty_slots
    local reserved_slot
    local down_block
    local target_logs
    local task_end_time
    local target_saplings
    local miner_data
    local mine_tree_sub_task
    local block
    local where_sapling
    local sapling_count
    local sapling_excess


    -- Check assumptions

    -- We can assume we have a tool, if breaking fails due to not having a tool,
    -- we will return there.

    -- Facing log or sapling
    local check_block = wb:inspect()
    print("[Tree chop] : Looked forwards")
    if not check_block then
        print("[Tree chop] : No block seen")
        -- Can't possibly be a log or sapling.
        goto sapling_check
    end

    print("[Tree chop] : Checking if the block was a log or leaves")
    facing_sapling = helpers.arrayContains(check_block.tag, sapling_tag)
    facing_log = helpers.arrayContains(check_block.tag, log_tag)
    print("[Tree chop] : Done.")

    -- Find if we have saplings, and what the highest empty slot is.
    ::sapling_check::

    -- Pre-sort the inventory to make room at the front.
    print("[Tree chop] : Inventory pushback")
    task_helpers.pushInventoryBack(wb)

    -- search in reverse since we just pushed everything backwards.
    print("[Tree chop] : Inventory find item")
    sapling_slot = wb:inventoryFindTag(sapling_tag, true)
    print("[Tree chop] : Count empty slots")
    empty_slots = wb:countEmptySlots()

    -- If there are no empty slots for both the logs and saplings ( if
    -- we dont have some already ) we cannot continue, as our inventory would be full.
    if empty_slots == 0 or (empty_slots <= 1 and sapling_slot ~= nil) then
        task_helpers.throw("assumptions not met")
    end
    print("[Tree chop] : Sapling assumptions met")

    print("[Tree chop] : Moving saplings into slot 1 if needed")
    -- Pull the saplings into slot 1 if it exists
    if sapling_slot ~= nil then
        -- Slot should be empty.
        task_helpers.assert(wb:transferFromSlotTo(sapling_slot, 1))
        sapling_slot = 1

        -- Fix the gap that made, even though this does not matter at all lmao
        ---@type boolean[]
        reserved_slot = {}
        reserved_slot[1] = true
        task_helpers.pushInventoryBack(wb, reserved_slot)

        -- Select the sapling
        wb:select(1)
    end

    print("[Tree chop] : Possibly skipping sapling placement")
    -- If there is already a sapling or log we can skip placement
    if (facing_log or false) or (facing_sapling or false) then
        goto assumptions_met
    end

    print("[Tree chop] : Possibly skipping sapling placement")
    -- There wasn't a sapling or log, was it empty?
    if not check_block then
        -- Invalid position, non-tree block in front of turtle.
        task_helpers.throw("assumptions not met")
    end

    print("[Tree chop] : Sapling needs to be placed")
    -- We need to place a sapling. If we don't have any, we cannot continue.
    if not sapling_slot then
        task_helpers.throw("assumptions not met")
    end
    -- This cannot be nil now
    ---@cast sapling_slot number
    print("[Tree chop] : We have a sapling")

    -- Check the block where we would be placing the sapling. It must be some kind of dirt.
    -- ^^^ This check will no longer work in Minecraft 26.1
    -- We already checked that the block in front of us is air
    print("[Tree chop] : Forward")
    task_helpers.assert(wb:forward())
    print("[Tree chop] : Inspect down")
    down_block = wb:inspectDown()
    print("[Tree chop] : Checking if the block is valid for a sapling")
    if sapling_slot ~= nil and down_block ~= nil then
        if helpers.arrayContains(down_block.tag, "minecraft:dirt") then
            task_helpers.assert(wb:stepBack())
            -- Place the sapling
            task_helpers.assert(wb:place())
            goto assumptions_met
        end
    end

    print("[Tree chop] : Block not valid")

    -- If we made it here, we missed the assumptions we needed.
    -- IE, we have:
    -- - No log
    -- - No placed sapling
    -- - No sapling item with a valid placing location
    -- - No bitches
    task_helpers.throw("assumptions not met")

    ::assumptions_met::
    print("[Tree chop] : Needed assumptions have been met, task can run.")

    -- If no target is set, we can just set this to a stupidly high number.
    target_logs = task_data.target_logs or 999999999
    ---@type number
    ---@diagnostic disable-next-line: undefined-field
    task_end_time = (task_data.timeout * 1000) + os.epoch("utc")
    target_saplings = task_data.target_saplings or 16

    -- The mining sub-task is allowed to burn logs while mining if needed.
    -- No timeout, since it should just be one tree... unless it gets stuck
    -- in a forest, which actually is very funny and i do not care, the
    -- inventory will eventually be full.
    ---@type RecursiveMinerData
    miner_data = {
        name = "recursive_miner",
        mineable_tags = {log_tag, leaves_tag},
        fuel_patterns = {"log"}
    }

    -- Each tree is expected to give us at least 4 logs, which at 15 fuel per
    -- log, that should always be net positive. Thus the sub-task should
    -- easily be able to refuel itself. Thus the fuel threshold is just the
    -- same as the incoming task.
    ---@type TaskDefinition
    mine_tree_sub_task = {
        fuel_buffer = config.definition.fuel_buffer,
        return_to_facing = true,
        return_to_start = true,
        task_data = miner_data
    }

    -- Start the loop!
    while true do
        -- Yield to the OS
        print("[Tree chop] : Yielding to OS")
        task_helpers.taskYield()

        -- Have we met our goal?
        print("[Tree chop] : Goal check")
        if wb:inventoryCountPattern("log") >= target_logs then
            -- Goal met!
            break
        end

        -- Do we still have time?
        print("[Tree chop] : Time check")
        ---@diagnostic disable-next-line: undefined-field
        if os.epoch("utc") >= task_end_time then
            -- Out of time!
            break
        end

        -- Is there a log in front of us?
        print("[Tree chop] : Inspecting...")
        block = wb:inspect()

        -- If there is nothing there at all, that's wrong, since we should have
        -- placed a sapling, or exited if we ran out of saplings.
        task_helpers.assert(block ~= nil)

        -- Block cannot be nil now.
        ---@cast block Block

        -- If its not a log, it must be a sapling, and we need to wait.
        -- Theoretically the block in front of this turtle could be magically
        -- swapped out, but in that case the task would eventually just time out.
        if not helpers.arrayContains(block.tag, log_tag) then
            -- Nothing to do yet.
            print("[Tree chop] : No tree, need to wait.")
            goto wait_for_tree
        end

        print("[Tree chop] : Tree ready!")

        -- A tree is present! Mine it!
        print("[Tree chop] : Running subtask...")
        task_helpers.spawnSubTask(config, mine_tree_sub_task)
        print("[Tree chop] : Subtask done.")

        -- Tree mined!

        -- The sapling slot may have moved if we placed our last sapling last time.
        -- Searches upwards, since this will almost always be slot 1.
        print("[Tree chop] : Make sure the saplings are still in the right spot")
        where_sapling = wb:inventoryFindTag(sapling_tag)

        if where_sapling == nil then
            -- Ran out of saplings!
            print("[Tree chop] : Ran out of saplings!")
            task_helpers.throw("assertion failed")
        end
        -- We must have a slot with saplings then.
        ---@cast where_sapling number

        -- Did the sapling slot move?
        if where_sapling ~= 1 then
            print("[Tree chop] : Saplings moved, moving back into slot 1...")
            -- Just move the saplings into slot 1.
            -- If we're full enough to not be able to do this swap, chances are
            -- that the saplings would already in slot 1 anyways. So this
            -- Assertion failing is unlikely.
            task_helpers.assert(wb:swapSlots(where_sapling, 1))
            print("[Tree chop] : Done.")
        end

        -- We may now have extra saplings. Burn them.
        print("[Tree chop] : Burn extra saplings...")
        sapling_count = wb:inventoryCountTag(sapling_tag)
        sapling_excess = sapling_count - target_saplings

        if sapling_excess > 0 then
            print("[Tree chop] : There are excess saplings.")
            -- Have some to burn!
            -- If we have more than a stack to burn, that means we can safely
            -- burn the entire first slot. it should be impossible to gain more
            -- than a stack of saplings per tree chop anyways.
            sapling_excess = math.min(sapling_excess, 64)

            -- Try to burn them. This should almost always work unless we already
            -- have a TON of fuel for some reason, but in that case, its fine to
            -- just ignore the extra saplings, they'll eventually just entirely
            -- clog the inventory and end the task, which is okay.
            print("[Tree chop] : Burning.")
            wb:refuel(sapling_excess)

            -- If slot 1 is now empty, we need to swap saplings into it again.
            if wb:getItemCount(1) == 0 then
                print("[Tree chop] : Slot one now empty, re-arranging...")
                where_sapling = wb:inventoryFindTag(sapling_tag)
                -- There had to've been more than one stack
                ---@cast where_sapling number

                -- This should almost always work, unless we are both completely
                -- full of items, AND full of fuel.
                task_helpers.assert(wb:swapSlots(where_sapling, 1))
            end
        end
        print("[Tree chop] : Done burning")

        -- We don't need to refuel with logs here, since the sub-task
        -- auto-refuels with them, and will either overshoot, or end up at
        -- exactly the amount we need.

        -- Place the next sapling!
        -- We for sure have a sapling at this point, this could only fail if there
        -- is somehow a block in front of us after cutting down the tree.
        print("[Tree chop] : Placing the next sapling...")
        task_helpers.assert(wb:place())
        print("[Tree chop] : Done!")

        -- Time to wait for the next tree to grow!
        ::wait_for_tree::
        print("[Tree chop] : Waiting for the next tree...")
        -- According to some random person, trees take on average ~1000 seconds to grow
        -- (https://www.minecraftforum.net/forums/minecraft-java-edition/discussion/2937790-tree-growth-rate)

        -- It's better to under-shoot the wait amount than to over-shoot it. So
        -- we'll sleep for one minute.
        task_helpers.taskSleep(60)
    end

    -- All done!
    -- This should be safe since we return to the start position after every tree,
    -- we don't pop walkback.
    return task_helpers.try_finish_task(config)
end

return tree_chop