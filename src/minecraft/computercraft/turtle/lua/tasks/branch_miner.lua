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
--- @field total_blocks_mined number -- Total number of blocks mined during the task

--- Helper function to check if we have enough fuel to keep going, and refuel
--- if we need to / can.
---
--- Returns a boolean on wether or not the task can continue.
--- @param task_data TurtleTask
--- @return boolean
function fuel_check(task_data)
    local wb = task_data.walkback
    local inner_data = task_data.definition.task_data
    ---@cast inner_data BranchMinerData
    local fuel_needed = 0

    -- Walkback budget only matters if we need to return to the starting position.
    if task_data.definition.return_to_start then
        fuel_needed = fuel_needed + wb:cost()
    end

    fuel_needed = fuel_needed + task_data.definition.fuel_buffer

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
function inventory_check(wb, discardables)
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

--- Helper function to check a new position for ores to recurse into.
---
--- Takes into account what blocks are currently wanted.
---
--- Returns true if recursive mining could be started from this position.
function check_and_recurse()
    -- TODO: filter the list of blocks to only the blocks we still want
end


--- Helper function to run a branch off of the side of the trunk. Assumes the
--- branches will go left and right from the position that the turtle is currently
--- standing in, respecting its facing direction.
function do_branches()

end


--- Try to move forwards, mining incidental blocks if they are in the way.
---
--- Returns a boolean on wether the move succeeded or not.
--- @return boolean
function try_forwards()

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
        if not fuel_check() then
            -- Out of fuel!
            break
        end

        -- Inventory space?
        if not inventory_check then
            -- Out of room!
            break
        end

        -- We can keep going. Move forward unless its time for a branch.
        if current_trunk_distance % BRANCH_SPACING == 0 then
            -- Do the branch!
            do_branches()
        else
            -- Just move forwards.
            if not try_forwards() then
                -- Something we cannot break in our way. Must give up.
                break
            end
            current_trunk_distance = current_trunk_distance + 1
            -- See if there's anything we want to recurse into. This will
            -- automatically recurse for us.
            check_and_recurse()
        end

        -- Loop!
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    return task_helpers.try_finish_task(config, branch_miner_result)
end



return branch_miner