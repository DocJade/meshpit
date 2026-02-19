-- Task to mine for blocks, searching in a branching pattern.

-- === ===
-- Imports
-- === ===

local task_helpers = require("task_helpers")
local helpers = require("helpers")








-- === ===
-- Task-specific constants.
-- === ===


--- *The optimal spacing here is debated, and I'm not about to add to that argument,
--- so we will define "optimal" as what the minecraft wiki says it is.
---
--- https://minecraft.wiki/w/Tutorial:Mining#Efficiency_vs_Thoroughness
---
--- The gains above 6 blocks plateau, and the spacing of 9 looks suspicious, as
--- the efficiency drops at 10. I think 8 is a good middle ground.
---
--- Theoretically the best efficiency is just a straight line, but shut up.
local BRANCH_SPACING = 8



-- TODO: Make failing tasks still return data instead of returning nothing so we
-- can get at least a partial done list from this task.




--- Assumptions this task makes:
--- - The turtle is equipped with a tool that can break all of the requested kinds
---   of blocks. This also means you cannot request to break unbreakable blocks.
---
--- Task completion states:
--- - The task has been running for longer than the alloted time.
--- - Every requested block type has been mined at least the desired number of times
--- - The turtle cannot break a block that it wants to break. We return gracefully
---   with the same return format, containing what blocks we ended up mining.
--- - The turtle is not allowed to refuel with the items it's mining with, and
---   has ran our of the allowed fuel supply.
--- - The turtle has ran out of inventory space (turtle is required to always
---   have one empty slot) and there was nothing we could discard.
---
--- Task failures states:
--- - The turtle is unable to return to the starting position for some reason.
---   IE there are blocks in the way of the walkback so the turtle is stuck.
---
--- Notes:
--- - It is highly unlikely that any mining will happen if you pass in no incidental
---   blocks. If you know you are already starting directly next to the block you
---   want to mine, use the recursive_miner task instead.

--- The configuration for the search_mine task.
---
--- Be aware that if timeout and trunk_length are not set, this task will go forever
--- until it gets all of the blocks its looking for, or runs out of fuel.
--- @class BranchMinerData
--- @field name "branch_miner"
--- @field desired DesiredBlocks -- See DesiredBlocks.
--- @field incidental IncidentalBlocks? -- See IncidentalBlocks.
--- @field discardables DiscardableItems? -- See DiscardableItems.
--- @field fuel_items FuelItems? -- See FuelItems.
--- @field timeout number? -- Maximum number of seconds to spend in this task. May be nil to continue mining until other limits are hit.
--- @field trunk_length number? -- Maximum distance to mine forwards. May be nil to continue mining until other limits are hit.




--- Desired blocks to mine. The blocks contained within should be ordered by
--- preference, as the blocks at the front of the list will be mined first. Do
--- note that if you wish to self-refuel it may be a good idea to always put
--- blocks that can be burnt as fuel at the top of the priority list.
---
--- This is an array of blocks, paired with the mining amounts. When the desired
--- amount of blocks of a kind have been mined, these blocks will no-longer be
--- passed into recursive_miner, and thus will be skipped over if seen.
---
--- For flexibility, the blocks within the array are described in such a way that
--- you can put multiple blocks into one block, combining names or tags if desired.
--- Thus you can group together the blocks into groups, and once that group has
--- seen the specified amount of blocks mined, the entire group will be marked
--- as finished.
---
--- The desired_total is how many blocks total that match this group need to be
--- mined to mark the group as completed.
---
--- `mined` must be set to zero, or not set at all.
---
--- @class DesiredBlocks
--- @field groups {group: BlockGroup, desired_total: number, mined: number|nil}[]

--- Groups of blocks, or singular blocks. See DesiredBlocks for more info.
---
--- The array fields must not be nill. Use an empty table instead.
--- @class BlockGroup
--- @field names_patterns string[] -- Patterns that will match the names of blocks in the group.
--- @field tags string[] -- Tags that blocks in this group may have.

--- Incidental blocks are blocks that are allowed to be mined, but are not
--- searched for during the mining process. IE, while boring tunnels to search
--- for desired blocks, these are the blocks that are allowed to be mined.
---
--- There is no quota for these blocks.
--- @class IncidentalBlocks
--- @field groups BlockGroup[]

--- This contains all of the items that the mining task is allowed to discard
--- when the inventory of the turtle gets too full. This is a priority list,
--- items first in this list will be discarded first.
---
--- When items are discarded, the turtle will search all of its slots once for
--- every item in this list until it finds some that it can discard. The turtle
--- will then find every slot containing this item, and discard the slot with
--- the least of this item in it, unless `discard_all` is set, in which case it
--- will drop all of them.
---
--- It is recommended to mark `discard_all` on groups of items that are very
--- common, such as cobblestone.
---
--- These are pattern strings that match the names of items. Be careful not to
--- make the patterns too broad.
--- @class DiscardableItems
--- @field patterns string[]

--- All of the items that the turtle is allowed to burn to refuel itself while
--- mining.
---
--- These are pattern strings that match the names of items. Be careful not to
--- make the patterns too broad.
--- @class FuelItems
--- @field patterns string[]

--- The result of the branch miner task.
--- Uses the same MinedBlocks structure from recursive_miner.
--- Go look over there for how MinedBlocks works. lol.
---
--- @class BranchMinerResult
--- @field name "branch_miner_result"
--- @field mined_blocks MinedBlocks -- Tracks which blocks were mined and how many
--- @field total_blocks_mined number -- Total number of blocks mined during the task, including incidentals.

--- Helper function to check if we have enough fuel to keep going, and refuel
--- if we need to / can.
---
--- Returns a boolean on wether or not the task can continue.
--- @param task TurtleTask
--- @return boolean
local function fuel_check(task)
    local wb = task.walkback
    local inner_data = task.definition.task_data
    ---@cast inner_data BranchMinerData
    local fuel_needed = 0

    -- Walkback budget only matters if we need to return to the starting position.
    if task.definition.return_to_start then
        fuel_needed = fuel_needed + wb:cost()
    end

    fuel_needed = fuel_needed + task.definition.fuel_buffer

    if fuel_needed < wb:getFuelLevel() then
        -- Nothing to do
        return true
    end

    -- Need to refuel, try to find a fuel.
    local f_items = inner_data.fuel_items
    if f_items == nil then
        -- Nothing we can do
        return false
    end

    if task_helpers.tryRefuelFromInventory(wb, f_items.patterns) then
        -- Able to refuel!
        return true
    end

    -- No fuel to be had.
    return false

end

--- Helper function to check that we still have an empty inventory slot, or
--- discard items if we need to free up slots.
---
--- Returns a boolean on wether or not the task can continue.
--- @param wb WalkbackSelf
--- @param discardables DiscardableItems
local function inventory_check(wb, discardables)
    -- If there's a free slot, nothing to do.
    if wb:haveEmptySlot() then return true end

    local slot_to_discard = nil

    -- Need to discard something.
    for _, pattern in discardables do
        local best_slot = nil
        local lowest_count = math.huge

        -- First see if that item even exists before looking harder
        best_slot = wb:inventoryFindPattern(pattern)

        -- No need to go further if this doesn't exist
        if best_slot == nil then
            goto skip_filter
        end

        lowest_count = wb:getItemCount(best_slot)

        -- See if there are any slots better than this
        for slot = best_slot, 16 do
            -- Quicker than checking strings
            local count = wb:getItemCount(slot)
            if (count >= lowest_count) or count == 0 then
                goto continue
            end

            -- Less items, could it be?
            if wb:compareTwoSlots(best_slot, slot) then
                -- New PB!
                lowest_count = count
                best_slot = slot
            end

            ::continue::
        end

        -- This is now the slot we want to toss.
        slot_to_discard = best_slot
        break

        ::skip_filter::
    end

    -- Did we find anything?
    if slot_to_discard == nil then
        -- Shucks.
        return false
    end

    -- Drop that slot. This is fine to go into a block, i checked. So we always
    -- just go up.
    local old_slot = wb:getSelectedSlot()
    wb:select(slot_to_discard)
    local dropped = wb:dropUp()
    wb:select(old_slot)

    if not dropped then
        -- ???? This should always work.
        task_helpers.throw("assumptions not met")
    end

    -- Space is now cleared up.
    return true
end

--- Filter out the blocks we want to only the ones which have not hit their mined
--- limit yet.
---
--- Does not modify the incoming table, and the returned table is built out of
--- references to the original table, thus you can modify it to update values
--- in the main table if needed.
--- @param wanted_blocks DesiredBlocks
--- @return DesiredBlocks
local function filter_wanted_blocks(wanted_blocks)
    --- @type DesiredBlocks
    local copy = {
        groups = {}
    }

    for _, group in ipairs(wanted_blocks.groups) do
        if group.desired_total >group.mined then
            -- Add it!
            copy.groups[#copy.groups + 1] = group
        end
    end

    return copy
end

--- Helper function to check a new position for ores to recurse into.
---
--- Takes in the entire task, as this may spawn a sub- task. Also takes in the
--- timeout timestamp to force the recursive miner to stop early if needed.
---
--- Takes into account what blocks are currently wanted.
---
--- Automatically does the recursive mining if needed, and updates the desired
--- blocks list automatically with how many blocks were mined.
--- @param task TurtleTask
--- @param task_result BranchMinerResult
--- @param timeout number
local function check_and_recurse(task, task_result, timeout)
    local task_data = task.definition.task_data
    --- @cast task_data BranchMinerData

    local wb = task.walkback

    -- Filter out for the blocks we still want
    local filtered = filter_wanted_blocks(task.definition.task_data.desired)

    -- If no blocks are desired, we have no need to recurse. Plus this should
    -- have been caught in the main loop anyways.
    if #filtered.groups == 0 then
        return
    end

    -- We can just do a spin scan since it takes the same amount of rotations as
    -- just looking left and right.
    wb:spinScan()

    local our_pos = wb.cur_position.position
    local our_facing= wb.cur_position.facing

    -- Get to know our neighbors, sans potato casserole.
    local neighbors = helpers.GetNeighborBlocks(our_pos, our_facing)

    -- We only need to find one matching neighbor at all, since recursive miner
    -- will scan in every direction again after this.
    local found_something = false
    for neighbor in neighbors do
        local the_block = wb:blockQuery(neighbor)
        -- This checks for nil for us.
        if helpers.block_wanted(the_block, filtered.groups) then
            found_something = true
            break
        end
    end

    -- Something to do?
    if not found_something then return end

    -- Yes! Run the recursive miner.

    -- Sum up all of the blocks we want to mine to set a hard limit on recursive_miner
    local mine_limit = 0
    for _, group in ipairs(filtered.groups) do
        mine_limit = mine_limit + (group.desired_total - group.mined)
    end

    -- Same timeout as the base task.

    --- @type RecursiveMinerData
    local recurse_data = {
        name = "recursive_miner",
        mineable_groups = filtered.groups,
        blocks_mined_limit = mine_limit,
        fuel_patterns = task_data.fuel_items.patterns,
        timeout = timeout
    }

    --- @type TaskDefinition
    local sub_task = {
        fuel_buffer = task.definition.fuel_buffer,
        return_to_facing = true,
        return_to_start = true,
        task_data = recurse_data,
    }

    -- Run the recursive miner!
    local success, data = task_helpers.spawnSubTask(task, sub_task)

    -- Did that work?
    if not success then
        -- Well. Shoot.
        ---@cast data TaskFailure

        -- TODO: Some sort of error handling here.
        print("Branch miner subtask died!")
        print("Reason:")
        print(data.reason)
        print("Stack trace:")
        print(data.stacktrace)
        task_helpers.throw("sub-task died")
    end

    -- All good!
    --- @cast data TaskCompletion
    local result = data.result
    --- @cast result RecursiveMinerResult

    -- Update the groups with the amount of mined blocks.
    local total_mined = 0
    for index, amount_mined in ipairs(result.mined_blocks) do
        local inner_group = filtered.groups[index]
        inner_group.mined = inner_group.mined + amount_mined
        total_mined = total_mined + amount_mined
    end

    -- Update the task result
    task_result.total_blocks_mined = task_result.total_blocks_mined + total_mined

    -- All done! It's the main loop's job to refuel and such if needed.
end

--- Try to move forwards, mining incidental blocks if they are in the way.
---
--- Returns a boolean on wether the move succeeded or not.
--- @param task TurtleTask
--- @param task_result BranchMinerResult
--- @return boolean
local function try_forwards(task, task_result)
    local wb = task.walkback
    local task_data = task.definition.task_data
    --- @cast task_data BranchMinerData
    local incidentals = task_data.incidental or {}
    -- Usually there is a block in front of us, but if there isn't, thats fine
    -- too.
    -- TODO: this will not allow the turtle to move through lava or water,
    -- walkback should have a method to check if the position in front of us is
    -- enterable.
    local block = wb:inspect()
    if block == nil then
        -- Open space, skip mining
        goto done_mining
    end

    -- There is a block in front of us, can we mine it?
    if helpers.block_wanted(block, incidentals.groups) then
        -- We can mine it. Go for it.
        if not wb:dig() then
            -- Failed to mine it! Must be something up with either the list or
            -- ...something else IDK. Regardless, we cannot move
            return false
        end
    else
        -- We are not allowed to mine this.
        -- Do note that we did not check the wanted_blocks list, as we assume that
        -- the caller would have already cleared out any neighboring blocks that
        -- were wanted already.
        return false
    end

    -- We mined a block.
    task_result.total_blocks_mined = task_result.total_blocks_mined + 1

    ::done_mining::

    -- Move into the space
    if not wb:forward() then
        -- Can't go for some reason. Don't care that much. Just say we can't
        -- keep going.
        -- TODO: In the future maybe this should care about falling blocks.
        return false
    end

    return true
end

--- Loop for just one branch. Assumes we have already been rotated.
--- @param task TurtleTask
--- @param task_result BranchMinerResult
--- @param timeout number
local function branch_time(task, task_result, timeout)
    local wb = task.walkback
    local incidental = task.definition.task_data.incidental or {}
    -- We assume the first block we look at would have already been
    -- recursively mined if it matched our list.

    -- The branch depth is the same as the spacing.
    -- TODO: This should have a setting in the future.
    for _ = 1, BRANCH_SPACING do
        -- Stop early if needed
        ---@diagnostic disable-next-line: undefined-field
        if os.epoch("utc") > timeout then
            break
        end

        -- Just move forwards.
        if not try_forwards(task, task_result) then
            -- Something we cannot break in our way. However, branches are
            -- allowed to just end early if they cannot go any further.
            break
        end
        -- Recurse if needed.
        check_and_recurse(task, task_result, timeout)
    end

    -- Went as far as we could, or as deep as requested.
end



--- Helper function to run a branch off of the side of the trunk. Assumes the
--- branches will go left and right from the position that the turtle is currently
--- standing in, respecting its facing direction.
--- @param task TurtleTask
--- @param task_result BranchMinerResult
--- @param timeout number
local function do_branches(task, task_result, timeout)
    local wb = task.walkback
    -- Right branch first
    wb:turnRight()
    branch_time(task, task_result, timeout)
    -- Turn around, and do the other side
    wb:turnRight()
    wb:turnRight()
    branch_time(task, task_result, timeout)
    -- Final turn, and we're done.
    wb:turnRight()
end







-- TODO: we shouldn't care about walkback fuel costs if we aren't required to
-- return to the start position of the task.


--- Mines for specified blocks in a branch pattern. Will start mining forwards
--- from whatever position this turtle started from.
---
--- IE, the turtle will mine in a direction for the optimal* number of blocks
--- before turning to the side, mining for `branch_depth` blocks, then returning
--- to the trunk, spinning 180 degrees, and branch again in the opposite direction.
---
--- *see the global at the top of the file.
---
--- Takes in a TurtleTask. See BranchMinerData for the sub-config.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function branch_miner(config)
    local wb = config.walkback

    -- Pre-checks.

    -- Right task?
    if config.definition.task_data.name ~= "branch_miner" then
        task_helpers.throw("bad config")
    end

    -- This must be the right task.
    local task_data = config.definition.task_data
    --- @cast task_data BranchMinerData

    -- Something to mine?
    if #task_data.desired.groups == 0 then
        task_helpers.throw("bad config")
    end

    -- Enough fuel?
    if config.definition.fuel_buffer > wb:getFuelLevel() then
        task_helpers.throw("out of fuel")
    end

    -- Task deadline
    ---@diagnostic disable-next-line: undefined-field
    local stop_time = 9999999999999999999999 -- roughly the year 317 million
    if task_data.timeout ~= nil then
        ---@diagnostic disable-next-line: undefined-field
        stop_time = os.epoch("utc") + (task_data.timeout * 1000)
    end

    -- Max trunk length
    -- Ain't no way you're going more than 2 million blocks.
    local max_trunk_length = task_data.trunk_length or 2000000

    -- Clone the incoming wanted table so we don't accidentally update some random
    -- referenced table.
    local desired_blocks = helpers.deepCopy(task_data.desired)

    -- We'll store all of our state in here to make passing it around easier.
    local state = {
        desired_blocks = desired_blocks,
        -- What direction we're currently mining. 0 is forward, 1 is left branch, and 2 is right branch.
        current_phase = 0,
        -- How many blocks deep into the current branch we are.
        branch_depth = 0,
    }

    -- Return var
    --- @type BranchMinerResult
    local branch_miner_result = {
        name = "branch_miner_result",
        mined_blocks = {
            counts = {}
        },
        total_blocks_mined = 0
    }

    -- Add da groups
    for i = 1, #desired_blocks.groups do
        branch_miner_result.mined_blocks.counts[i] = 0
    end

    -- Commonly used functions and values
    local fuel_buffer = config.definition.fuel_buffer
    local current_trunk_distance = 0
    local discardables = config.definition.task_data.discardables or {}
    local incidental = config.definition.task_data.incidental or {}

    -- Main loop
    while true do

        -- Are all of our quotas met?
        local all_done = true

        for _, group_entry in ipairs(desired_blocks.groups) do
            local mined = group_entry.mined or 0
            if mined < group_entry.desired_total then
                -- Still have work to do.
                all_done = false
                break
            end
        end

        if all_done then
            break
        end

        -- Out of time?
        if os.epoch("utc") > stop_time then
            break
        end

        -- Max trunk distance hit?
        if max_trunk_length <= current_trunk_distance then
            break
        end

        -- Do we have enough fuel?
        -- This will automatically refuel if needed.
        if not fuel_check(config) then
            -- Out of fuel!
            break
        end

        -- Inventory space?
        if not inventory_check(wb, discardables) then
            -- Out of room!
            break
        end

        -- We can keep going. Move forward unless its time for a branch.
        if current_trunk_distance % BRANCH_SPACING == 0 then
            -- Do the branch!
            do_branches(config, branch_miner_result, stop_time)
        else
            -- Just move forwards.
            if not try_forwards(config, branch_miner_result) then
                -- Something we cannot break in our way. Must give up.
                break
            end
            current_trunk_distance = current_trunk_distance + 1
            -- See if there's anything we want to recurse into. This will
            -- automatically recurse for us.
            check_and_recurse(config, branch_miner_result, stop_time)
        end

        -- Loop!
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    return task_helpers.try_finish_task(config, branch_miner_result)
end



return branch_miner