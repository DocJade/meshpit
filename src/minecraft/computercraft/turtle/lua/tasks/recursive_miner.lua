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
--- - The limit of blocks to break has been hit.
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
--- @field blocks_mined_limit number? -- Maximum number of blocks to mine before exiting early. May be nil to continue until fuel runs out or timeout.
--- @field mineable_groups BlockGroup[] -- Groups of blocks that can be mined. Groups are ordered by priority.
--- @field fuel_patterns string[]? -- A list of string patterns that are allowed as fuel. For example, `coal` matches `minecraft:coal` or `minecraft:coal_block`

--- What blocks were mined during the task. Tracks at the group level.
---
--- When a block is mined, only the group that matched is incremented.
--- The counts array is parallel to the mineable_groups array passed in the config.
--- IE: counts[1] is the number of blocks mined from mineable_groups[1].
---
--- @class MinedBlocks
--- @field counts number[]

--- The result of the recursive miner.
---
--- TODO: Need to make this also somehow track fuels used in a way that makes
--- sense so that callers can know that we did indeed mine the blocks requested,
--- but some were used as fuel. No idea how to make this work for like coal ore
--- and such. Will do later.
---
--- mined_blocks
--- @class RecursiveMinerResult
--- @field name "recursive_miner_result"
--- @field mined_blocks MinedBlocks -- See MinedBlocks
--- @field total_blocks_mined number -- Total number of blocks mined during the task.



local helpers = require("helpers")
local task_helpers = require ("task_helpers")
local constants = require("constants")

-- Frequently used helper functions
local coordinatesAreEqual = helpers.coordinatesAreEqual
local arrayContains = helpers.arrayContains
local keyFromTable = helpers.keyFromTable
local findString = helpers.findString
local getAdjacentBlock = helpers.getAdjacentBlock
local isPositionAdjacent = helpers.isPositionAdjacent
local GetNeighborBlocks = helpers.GetNeighborBlocks

--- Helper function to check if a position has been seen within the list of seen
--- positions.
--- @param position_to_check CoordPosition
--- @param seen_blocks {[string]: true}
--- @return boolean
local function have_seen_position(position_to_check, seen_blocks)
    -- Key the position we're at
    local key = keyFromTable(position_to_check)

    -- This is never nil
    ---@cast key string

    -- Return if we have seen it.
    return seen_blocks[key]
end

--- Get all of the coordinate positions of neighboring blocks that we have
--- not yet examined.
--- @param position CoordPosition
--- @param facing CardinalDirection
--- @param seen_blocks {[string]: true}
--- @return CoordPosition[]
local function get_unseen_neighbor_blocks(position, facing, seen_blocks)
    local all_neighbors = GetNeighborBlocks(position, facing)

    ---@type CoordPosition[]
    local kept_neighbors = {}
    -- Discard the ones we've seen.
    for _, n in ipairs(all_neighbors) do
        if not have_seen_position(n, seen_blocks) then
            -- Haven't seen this one yet!
            kept_neighbors[#kept_neighbors+1] = n
        end
    end
    return kept_neighbors
end

--- This is a pre-check we can run before moving into a block to see if its worth
--- doing. IE, if we have already seen all of the neighbors of a block we would be
--- moving into, then there is no reason to move in there.
---
--- Takes in a position you are thinking about moving into, returns a boolean on
--- wether or not that move would yield new information.
---
--- Doesn't return a facing direction, since it just counts the neighbors.
--- @param maybe_move_here CoordPosition
--- @param seen_blocks {[string]: true}
--- @return boolean
local function moving_would_give_info(maybe_move_here, seen_blocks)
    -- If there is at least one block that has not been seen that you would be
    -- able to see from that maybe position, then its worth moving into.
    -- No need to provide accurate facing info.

    -- TODO: Improve this to split this check up to also allow for moving into
    -- positions that have no new info, but would allow for taking a shortcut.

    return #(get_unseen_neighbor_blocks(maybe_move_here, "n", seen_blocks) or {}) > 0
end

--- Check if a position wants to be mined.
---
--- This is slow, as it can iterate over all of the positions.
---
--- Returns a boolean, and the index into the array that the position is found
--- at, if any.
--- @param check_position CoordPosition
--- @param to_mine PositionWithReason[]
--- @return boolean, number|nil
local function position_wants_to_be_mined(check_position, to_mine)
    local saw_position = false
    local index_seen = nil

    -- We expect that almost all of the time, the block we are checking will be
    -- near the top of the list, thus we iterate backwards.

    for i = #to_mine, 1, -1 do
        if coordinatesAreEqual(to_mine[i].pos, check_position) then
            saw_position = true
            index_seen = i
            break
        end
    end
    return saw_position, index_seen
end

--- This is a post-check on movement. Call this after scanning!
---
--- If we have moved and are facing a block that we already want to mine,
--- it may be worth pulling it out of the queue early and mining it immediately.
---
--- I would expect that on average, since we're already facing in that direction,
--- it seems likely that by the time we pass this block again from the position
--- we originally wanted to mine it from, we would have rotated, as 3/4 rotations
--- would be facing the wrong way.
---
--- Additionally, this also means we can early break for blocks above and below
--- us, completely removing any need for rotation.
---
--- Due to how this check works, this really only works if you are in the center
--- of some already checked area.
---
--- Cases that make it worth it:
--- - We don't need to move into that position after mining it, since all of
---   its neighbors have already been seen, thus we save all of the movement
---   required to get to the other earlier position we wanted to break from.
---   IE: We mine the block early if stepping into it would give no info.
---
--- Does not modify incoming tables. You need to call mark_mined if you break
--- a block provided by this function.
---
--- Returned position (if any) is a reference. Do not modify it.
---
--- Returns a boolean if you should mine a block now, and the coordinate you
--- need to plug into mineAdjacent.
--- @param cur_position MinecraftPosition
--- @param seen_blocks {[string]: true}
--- @param to_mine PositionWithReason[]
--- @return boolean, CoordPosition[]
local function already_facing_shortcut(cur_position, seen_blocks, to_mine)
    local our_pos, our_facing = cur_position.position, cur_position.facing

    -- We only need to check forwards, up and down. However, the order here
    -- matters. We want to prefer a position that is the inverse of the usual
    -- priority list. I can't explain why, but this feels intuitively correct.
    -- TODO: Justify / prove this ^^^


    ---@type CoordPosition[]
    local check_positions = {}
    check_positions[#check_positions + 1] = getAdjacentBlock(our_pos, our_facing, "u")
    check_positions[#check_positions + 1] = getAdjacentBlock(our_pos, our_facing, "f")
    check_positions[#check_positions + 1] = getAdjacentBlock(our_pos, our_facing, "d")

    -- If we haven't seen these blocks, we can immediately skip them.
    -- We dont mark the blocks as wanted.

    -- Since this is called post-scan, we do not need to check if they are seen
    -- positions, we only care if we want to mine them.


    -- Check if mining those positions would give information. We will only keep
    -- ones that will NOT give information, since that would make them safe to
    -- mine without moving into.

    -- We do this before checking if we want to mine them, as it is cheaper to
    -- do these key lookups than it is to iterate through the list of
    -- blocks that we want to mine.
    --
    -- TODO: if we change the to_mine type to be an array of tuples that come
    -- with a key to test with, this would no longer be true. That would also
    -- be smarter.

    ---@type CoordPosition[]
    local no_info = {}
    for _, pos in ipairs(check_positions) do
        -- The ordering that we get from this does not matter, we only care if
        if not moving_would_give_info(pos, seen_blocks) then
            -- This is shortcut-able.
            no_info[#no_info+1] = pos
        end
    end

    -- Skip if there is no valid positions.
    if #no_info == 0 then
        return false, {}
    end

    -- There is at least one valid shortcut. We will return all of the shortcuts
    -- we see.
    ---@type CoordPosition[]
    local good_shortcuts = {}
    for _, pos in ipairs(no_info) do
        -- Check if we want to mine this block at all.
        if position_wants_to_be_mined(pos, to_mine) then
            -- Wanted! Return it!
            good_shortcuts[#good_shortcuts+1] = pos
        end
    end

    -- Maybe has valid shortcuts!
    return #good_shortcuts > 0, good_shortcuts
end

--- Mark a position as mined in our wanted list. If the incoming position was not
--- marked as wanted, this will panic, as we mined some random block.
---
--- Modifies `to_mine`, does not modify the incoming position.
---
--- Also updates the balance sheet, and total blocks mined.
--- @param mined_position CoordPosition
--- @param to_mine PositionWithReason[]
--- @param miner_return_value RecursiveMinerResult
--- @param did_you_break_it boolean
local function mark_mined(mined_position, to_mine, miner_return_value, did_you_break_it)

    -- Check if we actually needed to mine that position
    local wanted, index = position_wants_to_be_mined(mined_position, to_mine)

    -- We should never mine a block we did not want.
    task_helpers.assert(wanted)

    local the_block = to_mine[index]

    -- Update the statistics if needed.
    if did_you_break_it then
        -- god these are long lmao
        local val = miner_return_value.mined_blocks.counts[the_block.group_index]
        val = val + 1
        miner_return_value.mined_blocks.counts[the_block.group_index] = val

        -- We mined another block. Update total
        miner_return_value.total_blocks_mined = miner_return_value.total_blocks_mined + 1
    end

    -- Remove it from the list. Since it may not be at the end, we'll use the
    -- remove method. This is slower than just always removing from the end, but
    -- most commonly we will be mining blocks towards the end of the list anyways,
    -- so it shouldn't need to move too many items.
    table.remove(to_mine, index)
end

--- Take in a list of positions including their directions and calculates the
--- cost of doing all of the rotations in the order specified from some starting
--- facing direction.
--- @param starting CardinalDirection
--- @param directions table<CoordPosition, CardinalDirection>[]
--- @return number
local function calculate_turn_cost(starting, directions)
    local total = 0
    -- Needs to take into account the new facing direction after a turn.
    local current_facing = starting
    for _, d in ipairs(directions) do
        local moves = helpers.findFacingRotation(current_facing, d[2])
        total = total + #(moves or {})
        current_facing = d[2]
    end
    return total
end

--- Inspect the neighboring blocks that we've never seen before in the most
--- optimal order, then return what blocks we saw. May return 0 blocks.
---
--- Returns the neighboring blocks, and their position.
---
--- Can modify the facing direction of the turtle, the wanted list, and the seen
--- list.
--- @param wb WalkbackSelf
--- @param seen_blocks {[string]: true}
--- @return Block[], CoordPosition[]
local function smart_scan(wb, seen_blocks)
    local p, f = wb.cur_position.position, wb.cur_position.facing
    -- Find the directions that need to be scanned.
    local to_see = get_unseen_neighbor_blocks(p, f, seen_blocks)
    -- Bail if there is nothing to look at.
    if #to_see == 0 then
        return {}, {}
    end

    --- @cast to_see CoordPosition[]

    -- We will now look at all of those blocks, so mark them as seen now.
    for _, pos in ipairs(to_see) do
        local key = helpers.keyFromTable(pos)
        --- @cast key string
        seen_blocks[key] = true
    end

    -- Split the list of blocks into the ones with a vertical change, and the
    -- ones we have to rotate to face. Additionally, we will also keep track of
    -- we have seen our current facing position in this list, and what directions
    -- all of these positions are for a shortcut later.
    --- @type CoordPosition[]
    local verticals = {}

    --- @type table<CoordPosition, CardinalDirection>[]
    local horizontals = {}
    local saw_starting = false

    for _, see_p in ipairs(to_see) do
        if see_p.y == p.y then
            -- Horizontal. Get deltas and figure out the direction.
            local d_x, d_z = see_p.x - p.x, see_p.z - p.z
            local direction = helpers.mostSignificantDirection(d_x, d_z)
            saw_starting = saw_starting or f == direction
            horizontals[#horizontals+1] = {see_p, direction}
        else
            -- vert
            verticals[#verticals+1] = see_p
        end
    end

    -- If these are air (nil) they will not affect the table at all. Which is ok,
    -- since we always add to the end.
    --- @type Block[]
    local blocks_looked_at = {}

    -- We also now need to keep track of the positions looked at to make sure
    -- they stay in sync with blocks_looked_at.
    --- @type CoordPosition[]
    local positions_looked_at = {}

    -- Look up and down first, since those dont require anything fancy, or any
    -- rotation.
    local c_v = #verticals
    if c_v == 0 then
        -- Don't need to look up or down.
    else
        for _, v in ipairs(verticals) do
            local inspected
            if v.y - p.y > 0 then
                inspected = wb:inspectUp()
            else
                inspected= wb:inspectDown()
            end
            -- Only add if we saw something
            if inspected ~= nil then
                -- Not air
                blocks_looked_at[#blocks_looked_at+1] = inspected
                positions_looked_at[#positions_looked_at+1] = v
            end
        end
    end

    -- Now for the horizontal ones.

    -- Skip if there is nothing to do
    local c_h = #horizontals
    if c_h == 0 then
        return blocks_looked_at, positions_looked_at
    end

    -- We pre-sort the positions here, since if we moved straight upwards, we
    -- will need to rotate 3 times, but if the positions we check do not start
    -- at the direction we are currently facing, then we would spin more times
    -- than actually needed.

    -- IE: We start facing north, and the scan directions given to us are
    -- south, east, then west. This would result in us turning 5 times instead
    -- of just 3.

    -- Thankfully, the positions we get from get_true_neighbor_blocks is always
    -- ordered clockwise in the horizontal component. Thus, if the first position
    -- is not the position in front of us, we can "rotate" the entire array until
    -- it is.

    -- If the direction we are currently facing is not included, the logic is
    -- a bit more complicated. However, we can actually cover both of these cases
    -- by calculating the total number of rotations used in the array, then
    -- optimize to reduce that number.

    -- Best possible costs:

    -- 4                 : 3
    -- 3 Including start : 2
    -- 3 Otherwise       : 3
    -- 2 no gap, start   : 1
    -- 2 no gap, no start: 2
    -- 2 gaps, start     : 2
    -- 2 gaps, no start  : 3
    -- 1                 : irrelevant.

    -- notice how the best cost is always the same as the length, unless our
    -- current facing position is included within the list of moves, in which
    -- case the cost is reduced by one.

    -- Thus we can directly calculate the target cost.
    local target_cost = c_h - (saw_starting and 1 or 0)

    -- Gotos here, so we need to put the locals up here.

    local current_cost
    local first_distance
    local second_distance
    -- Because tables are just references, we can make a shorter binding here
    local t = horizontals

    -- We do not need to sort if there is only 1 position to look at, as there is
    -- no way to optimize how many rotations it will take.
    if c_h == 1 then
        goto done_sorting
    end


    -- Now we can permutate the array until we see the cost we want.
    current_cost = calculate_turn_cost(f, t)

    -- We might not need to sort.
    if target_cost == current_cost then
        -- Nice!
        goto done_sorting
    end

    -- If there are only 2 positions, we can immediately deduce the best combination
    if c_h == 2 then
        -- The only other possible permutation is swapping the two elements.
        -- Yes this works, and yes i hate it.
        t[1], t[2] = t[2], t[1]
        goto done_sorting
    end

    -- If there are 4 options, rotating the array until the first option is our
    -- facing position will yield the best option.

    -- 3 has a different pattern.
    if c_h == 3 then goto permute_three end

    -- Rotate the array till the first position is our facing position.
    while t[1][2] ~= f do
        t[1], t[2], t[3], t[4] = t[4], t[1], t[2], t[3]
    end

    goto done_sorting

    -- Three is a bit complicated, but basically, we check if the difference in
    -- the integer version of the direction has a difference of 1 between each
    -- faced direction.

    -- So we can just build the array ourself

    -- This is the same as just sorting the array based on distance. However, if
    -- there is a tie in the first 2 places on distance due to the starting position
    -- not being included in the 3 positions, that would result in 90, 180, 90 turns.
    -- Thus, we then will check again to see the difference between 1 and 2 from
    -- the start position. If they are the same, we can safely swap one of them
    -- into the last position.

    -- TODO: Man this is probably a bit wasteful since its making tables and such
    -- but idk this is the 5th or so thing i have tried tonight.

    ::permute_three::
    table.sort(t, function (a, b)
        local left = #(helpers.findFacingRotation(f, a[2]) or {})
        local right = #(helpers.findFacingRotation(f, b[2]) or {})
        return left < right
    end)

    -- Swap the final two elements if needed.
    first_distance = #(helpers.findFacingRotation(f, t[1][2]) or {})
    second_distance = #(helpers.findFacingRotation(f, t[2][2]) or {})
    if first_distance == second_distance then
        t[2], t[3] = t[3], t[2]
    end

    ::done_sorting::

    -- Now that we're finally done sorting, we can run through those positions.
    for _, sorted_pos  in ipairs(horizontals) do
        -- Turn
        wb:faceAdjacentBlock(sorted_pos[1])
        -- inspect, and store!
        local inspected = wb:inspect()
        if inspected ~= nil then
            blocks_looked_at[#blocks_looked_at+1] = inspected
            positions_looked_at[#positions_looked_at+1] = sorted_pos[1]
        end
    end

    -- We are finally done!
    return blocks_looked_at, positions_looked_at
end

--- Dig an adjacent position, and if that fails, die.
---
--- Returns a boolean if something was actually mined.
--- @param wb WalkbackSelf
--- @param pos CoordPosition
--- @return boolean
local function mine_or_die(wb, pos)
    local mine_result, mine_reason = wb:digAdjacent(pos)

    -- Check for actually failures, ignore "Nothing to dig here"
    if (not mine_result) and (mine_reason ~= "Nothing to dig here") then
        task_helpers.throw("assumptions not met")
    end
    return mine_result
end

--- Move into an adjacent position, and if that fails, die.
--- @param wb WalkbackSelf
--- @param pos CoordPosition
local function move_or_die(wb, pos)
    local move_result, move_reason = wb:moveAdjacent(pos)

    -- Check for actually failures, ignore "Nothing to dig here"
    if (not move_result) and (move_reason ~= "Nothing to dig here") then
        -- Throw the more specific fuel error if needed.
        if move_reason == "Out of fuel" then
            task_helpers.throw("out of fuel")
        end
        task_helpers.throw("assumptions not met")
    end
end

--- Automatically mine blocks that we know we can get rid of quickly after every
--- move.
---
--- This is guaranteed to not move or rotate the turtle.
---
--- If blocks are mined, to_mine is automatically updated.
--- @param wb WalkbackSelf
--- @param seen_blocks {[string]: true}
--- @param to_mine PositionWithReason[]
--- @param miner_return_value RecursiveMinerResult
local function post_movement_shortcuts(wb, seen_blocks, to_mine, miner_return_value)
    -- Check the shortcut
    local have_shortcut, go_mine = already_facing_shortcut(wb.cur_position, seen_blocks, to_mine)
    if not have_shortcut then
        -- nothing to do
        return
    end

    -- Shortcuts to mine!
    ---@diagnostic disable-next-line: undefined-field
    -- os.setComputerLabel("Shortcut!")

    -- There are shortcuts! Mine them and mark them.
    for _, pos in ipairs(go_mine) do
        -- Mine
        local mined = mine_or_die(wb, pos)
        -- Mark
        mark_mined(pos, to_mine, miner_return_value, mined)
    end
end

--- Pick the next position to mine. Peeks at the top of the stack and re-orders
--- it based on priorities and preferring to avoid rotation.
---
--- May (and most likely will) modify to-mine.
---
--- Uses walkback purely for positional data.
---
--- Returns the next position that should be mined. May not necessarily be the
--- top of the stack.
--- @param wb WalkbackSelf
--- @param to_mine PositionWithReason[]
--- @param seen_blocks {[string]: true}
--- @param mineable_groups BlockGroup[]
--- @return PositionWithReason
local function pick_next_mine(wb, to_mine, seen_blocks, mineable_groups)
    local p, f = wb.cur_position.position, wb.cur_position.facing

    -- Bail if there is nothing to do, or only one thing to do. As re-ordering
    -- those would be pointless.
    if #to_mine <= 1 then
        return to_mine[#to_mine]
    end

    -- Pop off things to mine from the top of the stack until we hit a position
    -- that is non-adjacent, or run out of positions. We will also attach a
    -- number to keep track of this position's score.
    --
    -- Remember that everything in popped is going to be references, so we cannot
    -- modify the positions, thus we clone them. Although we never change the
    -- positions, we just need to make sure we don't accidentally remove the
    -- position we are referencing when we add everything back on after sorting.
    --- @type {pwr: PositionWithReason, score: number}[]
    local popped = {}

    while true do
        if #to_mine - #popped == 0 then break end
        local peek = to_mine[#to_mine - #popped]
        if not helpers.isPositionAdjacent(p, peek.pos) then break end
        popped[#popped + 1] = { pwr = peek, score = 0 }
    end


    -- Scoring criteria:
    -- 1: -1 point for every rotation required to face the block to break.
    --    This does not effect up and down.
    -- 2: +1 point for ever position that would be revealed by mining that block
    --    and moving into it. Prioritizes filling out the search space, resulting
    --    in more shortcuts.
    -- 3: Variable amount of points added based on what position in the priority
    --    list the block that would be mined is. IE: If the list is 5 blocks
    --    long, the first block would give a score of 5, second would get 4, and
    --    so on.

    -- 1: Rotations
    for _, pop_pos in ipairs(popped) do
        -- Skip up and down
        if pop_pos.pwr.pos.y == wb.cur_position.position.y then
            local direction = helpers.mostSignificantDirection(pop_pos.pwr.pos.x - p.x, pop_pos.pwr.pos.z - p.z)
            local turns = #(helpers.findFacingRotation(f, direction) or {})
            pop_pos.score = pop_pos.score - turns
        else
            -- Going up and down appears to be worse for taking shortcuts.
            -- But its still way worth it if it reveals a lot of blocks, so it
            -- isn't penalized too hard.
            pop_pos.score = pop_pos.score - 1
        end
    end


    -- 2: Blocks revealed.
    -- Luckily we already have get_unseen_neighbor_blocks, so we can use that.
    for _, pop_pos in ipairs(popped) do
        -- Direction does not matter, since we're just counting.
        local revealed = get_unseen_neighbor_blocks(pop_pos.pwr.pos, "n", seen_blocks) or {}
        pop_pos.score = pop_pos.score + #revealed
    end

    -- 3: Mining priorities

    -- We actually want to incentivize this a little bit harder, since its very
    -- easy for this to get overpowered by check 2. Thus the bonus given is
    -- very large to practically separate the different kinds of blocks into groups.
    local scaling_factor = 20

    for _, pop_pos in ipairs(popped) do
        -- Grab what block this is.
        -- We already stored what kind it is so we can just use those stored values.
        -- extra swag too, since now we don't need to hit global state.

        -- Groups are ordered by priority,
        -- so lower index means higher priority.
        local group_index = pop_pos.pwr.group_index
        pop_pos.score = pop_pos.score + ((#mineable_groups - group_index) * scaling_factor)
    end


    -- Now sort by score.
    table.sort(popped, function (a, b)
        return a.score < b.score
    end)

    -- The items are now sorted where the best position is at the front of the list,
    -- thus we push them onto the top of the stack backwards.

    for i, pop_pos in ipairs(popped) do
        to_mine[#to_mine - #popped + i] = pop_pos.pwr
    end

    -- Return the new winner.
    return to_mine[#to_mine]

    -- TODO: Make this not prefer moving vertically, since that reduces our chances
    -- for shortcuts. The more horizontal movement, the better.
    -- Also score if mining a block and moving into its position would remove the
    -- last unknown neighbor of another block next to it.
    -- TODO: Make it so the post_movement_shortcuts can be called pre-movement as well?
    --   I just wanna make sure that if we move forwards into a position, we remove all
    --   of the shortcuts before we leave.
    -- TODO: It seems to still be picking sub-optimal rotations in the 3 case due to
    --       how we pick the next thing to mine here.

end

--- Task that recursively* mines blocks based on name or tag.
---
--- Never re-orders inventory, or changes what slot is selected.
---
--- *depth first search
---
--- Takes in a TurtleTask. See RecursiveMinerTask for the sub-config.
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
    if task_data.mineable_groups == nil or #task_data.mineable_groups == 0 then
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
    local mineable_groups = task_data.mineable_groups
    local stop_time = 9999999999999999999999; -- roughly the year 317 million
    if task_data.timeout ~= nil then
        ---@diagnostic disable-next-line: undefined-field
        stop_time = os.epoch("utc") + (task_data.timeout * 1000)
    end

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

    --- Tracks which group this position matched.
    --- @class PositionWithReason
    --- @field pos CoordPosition
    --- @field group_index number

    --- The list of blocks that need to be mined. New blocks are pushed onto the
    --- end of the list, as we look at the position at the top of the list to
    --- check if we are next to it.
    ---
    --- This also is used to track what filters a block matched, allowing us
    --- to keep track of what has been mined and why.
    ---
    -- This is an array of coordinate positions. Clone before adding them!
    ---@type PositionWithReason[]
    local to_mine = {}

    --- And finally, we set up the return type and pre-populate the arrays.
    --- @type RecursiveMinerResult
    local miner_return_value = {
        name = "recursive_miner_result",
        mined_blocks = {
            counts = {}
        },
        total_blocks_mined = 0
    }

    -- Pre-populate the result with zeros for each group
    for i = 1, #mineable_groups do
        miner_return_value.mined_blocks.counts[i] = 0
    end

    -- TODO: Pattern improvements!
    -- - While it shouldn't matter _too_ much, the pattern for mining trees looks
    --   pretty damn stupid.

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

        -- Can we not mine any more blocks?
        if task_data.blocks_mined_limit ~= nil and miner_return_value.total_blocks_mined >= task_data.blocks_mined_limit then
            -- Can't mine any more!
            break
        end

        -- Make sure we have an empty slot
        if not wb:haveEmptySlot() then
            -- Out of free slots!
            task_helpers.throw("inventory full")
        end

        -- Checks pass, keep going.

        -- Scan the neighboring blocks
        local neighbor_blocks, neighbor_positions = smart_scan(wb, seen_blocks)

        -- Skip if there is no blocks to mark
        if #neighbor_blocks == 0 then
            goto skip_marking
        end

        -- Mark the blocks as wanted if needed.
        for i = 1, #neighbor_blocks do
            local bool, group_index = helpers.block_wanted(neighbor_blocks[i], mineable_groups)
            if bool then
                -- We want this.
                -- No need to clone on the way in, as the positions are not borrowed
                -- from anywhere.
                -- This tracks which group matched for tracking later.
                -- We do not directly increment here, just in case the block magically
                -- disappears later.

                --- @cast group_index number

                --- @type PositionWithReason
                local p_w_r = {
                    pos = neighbor_positions[i],
                    group_index = group_index
                }

                to_mine[#to_mine+1] = p_w_r
            end
        end

        ::skip_marking::

        -- Neighbors have been checked. Is there anything to do?
        if #to_mine == 0 then
            -- Nothing left to mine!
            ---@diagnostic disable-next-line: undefined-field
            -- os.setComputerLabel("Out of things to mine!")
            break
        end

        -- There is something to mine!
        -- Mine the first thing as usual.
        local pos_to_mine = pick_next_mine(wb, to_mine, seen_blocks, mineable_groups)

        -- Peek at the top block, are we next to it?
        if not isPositionAdjacent(wb.cur_position.position, pos_to_mine.pos) then
            -- Walk back until we are next to it.
            while true do
                -- os.setComputerLabel("Moving back...")
                -- We should have enough fuel to do this if we did our math correct
                -- earlier.
                local r, _ = wb:stepBack()
                task_helpers.assert(r)

                -- Every time we step back, the priorities will change.
                pos_to_mine = pick_next_mine(wb, to_mine, seen_blocks, mineable_groups)

                if isPositionAdjacent(wb.cur_position.position, pos_to_mine.pos) then
                    break
                end

                -- While moving backwards, we may have a shortcut we can take.
                -- Shortcuts run _after_ the break check, since if we called this
                -- first, we could mine what is being looked for before the break.
                post_movement_shortcuts(wb, seen_blocks, to_mine, miner_return_value)
            end
        end


        -- We are now next to the block we need to mine.

        -- We will mine it, then move into it if moving in would provide information.
        -- Need to keep track if it was actually mined or not so we can update
        -- statistics.
        local actually_mined = mine_or_die(wb, pos_to_mine.pos)

        if moving_would_give_info(pos_to_mine.pos, seen_blocks) then
            -- Its worth moving in here. The scan will happen automatically on
            -- the next loop.
            move_or_die(wb, pos_to_mine.pos)
            post_movement_shortcuts(wb, seen_blocks, to_mine, miner_return_value)
        end

        -- Remove the old block from the list, adding it to the tally if we
        -- did actually mine something.
        mark_mined(pos_to_mine.pos, to_mine, miner_return_value, actually_mined)

        -- If we are running low on fuel, try to refuel from the inventory if we're allowed to.
        -- We always burn only one item per cycle to keep usage minimal and not overshoot.
        if movement_budget - 1 <= 0 then
            task_helpers.tryRefuelFromInventory(wb, fuel_patterns)
        end

        -- Loop! The next iteration will scan for more blocks and continue the
        -- recursion. Although it't not _really_ recursion, but shush.
    end

    -- Loop broken, its time to perform the walkback.
    -- The walkback is automatically preformed by try_finish_task.
    return task_helpers.try_finish_task(config, miner_return_value)
end



return recursive_miner