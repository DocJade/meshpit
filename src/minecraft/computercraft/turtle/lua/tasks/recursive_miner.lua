-- Takes in a list of kinds of blocks to mine, mines them, then returns to where
-- the task started, regardless if the return parameter is set.

--- Assumptions this task makes:
--- - The turtle is equipped with a tool that can break the blocks requested.
--- - The task is started next to a block (on any side) that matches the requested
---   kinds of block. This is not a hard requirement, but if the turtle doesn't
---   start next to one of these blocks, the mining operation will end before
---   mining a single block.
--- - The provided walkback is empty.
---
--- Task completion states:
--- - There are no more matching blocks to break
---
--- Task failures states:
--- - The turtle runs out of fuel.
--- - - IE, There are still blocks to mine, but the turtle does not have enough
---     fuel to move into new positions and still make it back to the starting
---     position while maintaining the requested fuel buffer.
--- - The inventory of the turtle has an item in every slot slots.
--- - - This is a quick check, we do this instead of needing to do more complicated
---     inventory tracking. If there is no more room in the inventory, we can
---     no-longer guarantee that broken blocks will go into the inventory.

--- The configuration for the recursive_miner task.
--- @class RecursiveMinerData
--- @field name "recursive_miner"
--- @field timeout number? -- Maximum number of seconds to spend in this task. May be nil to continue mining until fuel runs out.
--- @field mineable_names string[]? -- A list of block names that can be mined. Works in tandem with mineable_tags.
--- @field mineable_tags MinecraftBlockTag[]? -- A list of block tags that can be mined. Works in tandem with mineable_names.
--- @field fuel_patterns string[]? -- A list of string patterns that are allowed as fuel. For example, `coal` matches `minecraft:coal` or `minecraft:coal_block`

local helpers = require "helpers"
local task_helpers = require "task_helpers"

--- Check if an input block matches the required names or tags.
--- @param block Block|nil
--- @param wanted_names string[]?
--- @param wanted_tags string[]?
--- @return boolean
function block_wanted(block, wanted_names, wanted_tags)
    -- If the block is air, we do not care.
    if block == nil then return false end

    -- Check the name first, then the tags.
    if wanted_names then
        if helpers.arrayContains(wanted_names, block.name) then
            return true
        end
    end

    if wanted_tags then
        for _, tag in ipairs(block.tag) do
            if helpers.arrayContains(wanted_tags, tag) then
                return true
            end
        end
    end

    -- No match.
    return false
end

--- Get the coordinate positions of all the blocks next to the turtle.
---
--- The ordering of the directions in here influences the search pattern of the
--- turtle.
--- @param wb WalkbackSelf
--- @return CoordPosition[]
local function get_true_neighbor_blocks(wb)
    -- This should be fairly fast, since it's all just math, no actual
    -- game-state.
    -- Also, the ordering here gives us our priorities. First in last out.
    -- We prefer to go straight up, then going back down last.
    local neighbors = {}
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("d")
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("l")
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("b")
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("r")
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("f")
    neighbors[#neighbors + 1] = wb:getAdjacentBlock("u")
    return neighbors
end

--- Get all of the coordinate positions of neighboring blocks that we have
--- not yet examined.
--- @param wb WalkbackSelf
--- @return CoordPosition[]
--- @param seen_blocks {[string]: true}
local function get_neighbor_blocks(wb, seen_blocks)
    local all_neighbors = get_true_neighbor_blocks(wb)

    ---@type CoordPosition[]
    local kept_neighbors = {}
    -- Discard the ones we've seen.
    for _, n in ipairs(all_neighbors) do
        local key = helpers.keyFromTable(n)
        -- This cannot be nil... Not gonna check tho
        ---@cast key string
        if not seen_blocks[key] then
            -- Haven't seen this one yet!
            kept_neighbors[#kept_neighbors+1] = n
        end
    end
    return kept_neighbors
end

--- Task that recursively* mines blocks based on name or tag.
---
--- Never re-orders inventory, or changes what slot is selected.
---
--- *depth first search
---
--- Takes in a TurtleTask. see RecursiveMinerTask for the sub-config.
---@param config TurtleTask
---@return TaskCompletion|TaskFailure
local function recursive_miner(config)
    local wb = config.walkback
    -- Make sure the task name is correct
    if config.definition.task_data.name ~= "recursive_miner" then
        -- Wrong task.
        task_helpers.throw("bad config")
    end

    -- We now know for sure this is a mining task.
    local task_data = config.definition.task_data
    ---@cast task_data RecursiveMinerData

    -- There should be no previous steps in the walkback
    if wb:previousPosition() ~= nil then
        -- Walkback already had data in it.
        task_helpers.throw("bad config")
    end

    -- There must be some kind of block to mine
    if (task_data.mineable_names == nil) and (task_data.mineable_tags == nil) then
        -- Can't mine nothing!
        task_helpers.throw("bad config")
    end

    -- Task must start with more fuel than the buffer amount.
    if config.definition.fuel_buffer > wb:getFuelLevel() then
        task_helpers.throw("out of fuel")
    end

    -- We do not pre-check for the correct blocks, since we will find them in
    -- the loop if they do exist.



    -- TODO: Figure out how to make the movement budget also consider the
    -- block list we need to mine on the way back through the walkback. IE don't
    -- just walkback skipping all the blocks we've seen, mine them on the way
    -- back. Additionally, each block may reveal more blocks, so each additional
    -- block that we need to look at adds 5 more cost, as it could reveal more
    -- blocks to mine.
    -- Basically, we need some best-guess heuristic on how many blocks every
    -- mined block will reveal.

    -- TODO: When we run out of time, don't just end immediately, mine the
    -- blocks we already know about without recursing deeper.




    -- Just shorten the name of these
    local fuel_buffer = config.definition.fuel_buffer
    local fuel_patterns = task_data.fuel_patterns or {}
    local mineable_names = task_data.mineable_names or nil
    local mineable_tags = task_data.mineable_tags or nil
    local stop_time = 9999999999999999999999; -- roughly the year 317 million
    if task_data.timeout ~= nil then
        ---@diagnostic disable-next-line: undefined-field
        stop_time = os.epoch("utc") + (task_data.timeout * 1000)
    end

    -- Need to preserve what slot is selected.
    local original_slot = wb:getSelectedSlot()


    -- The list of the blocks we have checked. If a block is ever looked at, it
    -- goes in here. This is separate from the wb:all_seen_blocks since we need
    -- to differentiate blocks we've _checked_ and blocks we've seen, as we
    -- use blockQuery to check what kind of blocks exist at neighbors for
    -- simplicity instead of having to keep track of facing position and such.
    --
    -- We set blocks as seen after we confirm they are blocks that we have
    -- already checked for being the kind of block we want. This helps us not
    -- put duplicate blocks in the `to_mine` list.

    -- This is a Hashset of string coordinate positions.

    ---@type {[string]: true}
    local seen_blocks = {}

    -- The list of blocks that need to be mined. New blocks are pushed onto the
    -- end of the list, as we look at the position at the top of the list to
    -- check if we are next to it.

    -- This is an array of coordinate positions. Clone before adding them!
    ---@type CoordPosition[]
    local to_mine = {}

    -- TODO: Pattern improvements!
    -- - While it shouldn't matter _too_ much, the pattern for mining trees looks
    --   pretty damn stupid.
    -- TODO: Block priorities!
    -- - The incoming block list should be sorted by its priority, thus you can
    --   pick what blocks are mined first in the recursion. This will allow going
    --   for trunks early in trees, for example.

    -- Main loop
    while true do
        -- Calculate our current movement budget. We cannot update this
        -- manually, as we do not get informed when walkback trims occur.
        local movement_budget = wb:getFuelLevel() - fuel_buffer - wb:cost()
        -- Are we out of fuel?
        if movement_budget == 0 then
            -- Done mining!
            break
        end

        -- Are we out of time?
        if os.epoch("utc") > stop_time then
            -- Outta time!
            break
        end

        -- Make sure we have an empty slot
        if not wb:haveEmptySlot() then
            -- Out of free slots!
            task_helpers.throw("inventory full")
        end

        -- Checks pass, keep going.

        -- Scan all neighboring blocks
        -- Loop over the neighbors. This only returns ones we have not seen yet.
        local neighbors = get_neighbor_blocks(wb, seen_blocks)
        for _, neighbor in ipairs(neighbors) do
            local position_key = helpers.keyFromTable(neighbor)
            -- This should never be nil as CoordPosition meets the key rules. If
            -- this is not true, we have WAY more problems elsewhere.
            ---@cast position_key string

            -- We have now seen this position.
            seen_blocks[position_key] = true

            -- Look at the neighbor.
            -- Don't need to turn for above and below neighbors.
            -- Skip if the block is above or below
	        if wb.cur_position.position.y ~= neighbor.y then
	        	-- Vertical move, its up or down.
                local is_up = (neighbor.y - wb.cur_position.position.y) > 0
                if is_up then
                    wb:inspectUp()
                else
                    wb:inspectDown()
                end
	        else
                -- Turn to face it, and inspect it.
                local old_facing = wb.cur_position.facing
                wb:faceAdjacentBlock(neighbor)
                -- Even though faceAdjacentBlock will automatically inspect when turning,
                -- that does not account for the case where we did not turn.
                if old_facing == wb.cur_position.facing then
                    wb:inspect()
                end
            end

            -- Check if this is a block we want to mine
            -- We do not need to check for air, and since we are always checking
            -- neighboring positions, we know we have looked at this block due
            -- to the spin that happened before this loop.
            if block_wanted(wb:blockQuery(neighbor), mineable_names, mineable_tags) then
                -- We will mine this block later. Push to queue.
                to_mine[#to_mine+1] = helpers.clonePosition(neighbor)
            end
        end

        -- Neighbors have been checked. Is there anything to do?
        if #to_mine == 0 then
            -- Nothing left to mine!
            ---@diagnostic disable-next-line: undefined-field
            os.setComputerLabel("Out of things to mine!")
            break
        end

        local pos_to_mine = to_mine[#to_mine]

        -- Peek at the top block, are we next to it?
        if not wb:isPositionAdjacent(wb.cur_position.position, pos_to_mine) then
            os.setComputerLabel("Moving back...")
            -- Walk back until we are next to it.
            while true do
                -- We should have enough fuel to do this if we did our math correct
                -- earlier.
                local r, _ = wb:stepBack()
                task_helpers.assert(r)
                if wb:isPositionAdjacent(wb.cur_position.position, pos_to_mine) then
                    break
                end
            end
        end


        -- We are now next to the block we need to mine. Mine it AND Move into it.
        -- We loop here because falling blocks (sand/gravel/decaying leaves) or
        -- desyncs (?man idfk im just trying anything now) can cause the move to
        -- fail even if the dig returned "nothing to dig".
        local tries = 50
        while true do
            os.setComputerLabel("Breaking...")
            -- Doesn't select a tool, since it does not matter.
            local mine_result, mine_reason = wb:digAdjacent(pos_to_mine)

            -- Check for actually failures, ignore "Nothing to dig here"
            if not mine_result and mine_reason ~= "Nothing to dig here" then
                os.setComputerLabel(mine_reason)
                task_helpers.throw("assumptions not met: " .. tostring(mine_reason))
            end


            -- Move into the position we just mined. This should work as we just
            -- mined it out.
            os.setComputerLabel("Moving in...")
            local move_result, move_reason = wb:moveAdjacent(pos_to_mine)

            if move_result then
                -- Successfully moved!
                break
            elseif move_reason == "Out of fuel" then
                -- This should never happen due to how we loop, but idk.
                task_helpers.throw("out of fuel")
            else
                -- -- Movement obstructed. Something is amiss. We will try at most 50 times
                -- -- before assuming something is actually very broken. It could be
                -- -- that our facing direction got misaligned or that our position
                -- -- has drifted. I have no idea, and it would be hard to determine
                -- -- why here. Also this could be a falling block so... idk.
                -- -- Fifty sounds like a lot, and probably is. IDK how tall piles of
                -- -- sand or gravel could be. Better to overshoot than undershoot!

                -- -- From testing with trees, most of the time it seems to only need
                -- -- one retry.

                -- -- TODO: Move this retry logic into walkback, since we really should
                -- -- just be able to assume that if walkback returns that a block has
                -- -- been mined, it SHOULD BE GONE lol. Same for if checking for a block
                -- -- existing, might as well do it 5 times. Slower? Yes. Consistent?
                -- -- Also yes, and wildly more important. This should also let us
                -- -- turn the turtle action speed back up.

                -- -- Try again. This is self-slowing due to calling movement methods
                -- -- which are speed limited.
                -- tries = tries - 1
                -- if tries == 0 then
                --     -- Well shit.
                --     os.setComputerLabel("Movement obstructed after 50 tries.")
                --     task_helpers.throw("assumptions not met")
                -- end
            end
        end

        -- Remove the old block from the list
        os.setComputerLabel("Removing old...")
        to_mine[#to_mine] = nil

        -- If we are running out of fuel, refuel if we are allowed to.
        -- We always burn only one item to keep our usage minimal and not overshoot.
        -- Additionally, if we're mining items that we're allowed to smelt, those items
        -- would tend to be towards the top of the inventory, thus we iterate
        -- front to back.

        local did_refuel
        if #fuel_patterns == 0 or movement_budget - 1 > 0 then
            goto skip_refuel
        end

        did_refuel = false

        for i = 1, 16 do
            local item = wb:getItemDetail(i)
            -- Skip if there is no item
            if not item then goto continue end

            -- Does the name match?
            for _, pattern in pairs(fuel_patterns) do
                ---@cast pattern string
                -- Check if item matches
                if not helpers.findString(item.name, pattern) then goto bad_pattern end

                -- Valid item, try using it.
                wb:select(i)
                did_refuel = wb:refuel(1)
                wb:select(original_slot)

                -- Break out if that worked.
                if did_refuel then break end

                ::bad_pattern::
                -- That didn't work, keep going.
            end
            if did_refuel then break end
            ::continue::
        end
        ::skip_refuel::

        -- Loop! The next iteration will scan for more blocks and continue the
        -- recursion. Although it't not _really_ recursion, but shush.
    end

    -- Loop broken, its time to perform the walkback.
    -- The walkback is automatically preformed by try_finish_task.
    return task_helpers.try_finish_task(config)
end



return recursive_miner