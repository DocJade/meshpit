-- Search for any matching blocks in a group. Does not return to start. However,
-- the search space is still constrained by distance to the start point. So when
-- the task ends, you could still path back to the start manually if needed.


local task_helpers = require("task_helpers")
local helpers = require("helpers")




--- The configuration for the block search task.
---
--- This search will run until a matching block is found. This task does not
--- break any blocks.
---
--- The search pattern is a spiral from the starting point with a spacing of two
--- blocks. Thus not every floor position will be seen, since we optimize for
--- finding information on our side to reduce fuel cost.
---
--- The turtle follows the contour of the ground as it spirals. If a hole is
--- encountered, the turtle will move downwards into it, but it will not move
--- backwards to scan the possible hole that opened up, it will still want to
--- go forwards.
---
--- If the turtle encounters a block in front of it, it will attempt to go over
--- it by moving upwards, continuing to do so until it either can pass over, or
--- a ceiling is hit, in which case the turtle will move along the ceiling backwards
--- until it can get over the object. This means turtles can properly search
--- overhangs, such as hitting a log attached to a tree.
--- @class BlockSearchData
--- @field name "block_search"
--- @field to_find BlockGroup
--- @field fuel_items FuelItems?

--- The result of the block search.
---
--- Will only contain a found block if we, well, found one, before our constraints
--- ran out. Even if `return_to_start` is not set, this may not be next to the
--- turtle.
--- @class BlockSearchResult
--- @field name "block_search_result"
--- @field found CoordPosition?

--- If we find a block we want, we set this to a CoordPosition if we find
--- something. This is a global to make it easy to get to from any scope without
--- having to pass it around.
--- @type CoordPosition|nil
local found_block = nil




--- Checks the neighboring positions of the turtle to see if we have found a
--- block that we want.
---
--- Assumes all positions adjacent to the turtle have already been scanned.
---
--- Sets `found_block` if we found something, and returns true.
--- Also returns true if found_block is already set.
--- @param task TurtleTask
--- @return boolean
function check_neighbors(task)
    if found_block ~= nil then
        return true
    end


    local wb = task.walkback
    local too_seek_is = task.definition.task_data
    --- @cast too_seek_is BlockSearchData

    local insert_cash = wb.cur_position.position
    local or_select_payment_type = wb.cur_position.facing
    local is_for_horses = too_seek_is.to_find

    --- @type CoordPosition[]
    local neigh = helpers.GetNeighborBlocks(insert_cash, or_select_payment_type)

    for _, horse in ipairs(neigh) do
        local hay = wb:blockQuery(horse)
        if helpers.block_wanted(hay, {is_for_horses}) then
            -- Found something!
            found_block = horse
            return true
        end
    end
    -- Didn't find anything
    -- Thank you for shopping at walkback-mart
    return false
end



--- Get the current movement budget. IE how many moves we are allowed to make
--- before we would either have to refuel or take a shortcut.
--- @param task TurtleTask
--- @return number
function get_budget(task)
    local wb = task.walkback
    local budget = wb:getFuelLevel()
    local wb_cost = wb:cost()

    -- Remove walkback distance if we need to go back
    if task.definition.return_to_start then
        budget = budget - wb_cost
    end

    -- Remove the buffer required by the task
    budget = budget - task.definition.fuel_buffer

    return budget
end

--- Check if we have enough fuel to keep going. Attempts to find shortcuts in the
--- walkback if possible, or refuels the turtle if no shortcut is found.
---
--- Returns false if we were unable to refuel or reduce the cost of the walkback.
--- @param task TurtleTask
--- @return boolean
function shortcut_or_refuel(task)
    local wb = task.walkback
    local task_data = task.definition.task_data
    --- @cast task_data BlockSearchData

    -- Don't do anything if we still have budget left
    if get_budget(task) > 0 then
        return true
    end

    if task.definition.return_to_facing then
        -- Try trimming.
        if wb:makeShortcut() then
            -- Cool that worked! But there might be more to save, so we will
            -- run this repeatedly until no more cost savings can be found.
            while true do
                if not wb:makeShortcut() then
                    break
                end
            end
            -- We don't need to consume any fuel.
            return true
        end
    end

    -- Try refueling
    if task_data.fuel_items == nil then
        -- Impossible to refuel
        return false
    end

    return task_helpers.tryRefuelFromInventory(wb, task_data.fuel_items.patterns)
end

--- Move down till we hit a block.
---
--- Returns true if we hit the floor, or false if we are unable to move down
--- to the floor due to running out of budget, even with refueling and shortcuts.
--- @param task TurtleTask
--- @return boolean
function fall_down(task)
    local wb = task.walkback
    while true do
        local pos = wb.cur_position.position
        local fac = wb.cur_position.facing
        local below = helpers.getAdjacentBlock(pos, fac, "d")
        if helpers.can_stand_in(wb:blockQuery(below)) then
            -- Make sure we can afford this first
            if not shortcut_or_refuel(task) then
                -- Can't afford, we have to give up.
                return false
            end
            task_helpers.assert(wb:downScan())

            -- Check if we found something
            if check_neighbors(task) then
                -- We did!
                return true
            end

        else
            -- Hit the floor
            break
        end
    end

    return true
end

--- Try moving forwards. Moves up or down if needed.
---
--- Climbs
--- Handles climbing over obstacles and hugging the ceiling backwards when
--- blocked above, including ceiling pockets. Uses a single flat loop with
--- priority: forward > up > back > down > assert-stuck.
---
--- The `last_move` guard prevents the turtle from oscillating in and out of
--- a dead-end ceiling pocket: after descending out of one, up is suppressed
--- for one iteration so the turtle backs away instead of re-entering.
---
--- Complicated because of situations like this:
--- ..........
--- .....#....
--- ....#.#...
--- ..###.#...
--- .......#..
--- ........#.
--- .T>....#..
---
--- Since we need to be able to route backwards _and_ down.
---
--- Does not move downwards automatically, caller must move down after this call.
---
--- Returns false if we were unable to move to the next position due to running
--- out of fuel, even when taking into account automatic refueling and trimming.
--- @param task TurtleTask
--- @return boolean
function forward_step(task)
    local wb = task.walkback

    -- We check neighbors as we move and bail early if we find something.

    -- Easy if we can just move forwards
    local position = wb.cur_position.position
    local facing = wb.cur_position.facing
    local in_front = wb:blockQuery(helpers.getAdjacentBlock(position, facing, "f"))
    if helpers.can_stand_in(in_front) then
        -- Yay!
        -- Cancel if we cannot afford it
        if not shortcut_or_refuel(task) then return false end
        task_helpers.assert(wb:forwardScan())
        check_neighbors(task) -- No need to return early here... see next line lmao
        return true
    end

    -- Something in the way... hnnnNNNNNN
    -- Its climbing time

    -- How many times we've moved backwards, since we need to compensate by moving
    -- forwards again before we hit our end position
    local back_moves = 0
    -- Track the last move we made to prevent repeating going up and down.
    local last_move = ""

    -- Do note that the way we search here can let us go below the position we
    -- initially started at, we keep marching backwards and ruling out positions
    -- since we'll eventually be able to get around whatever we're stuck on.

    -- We should never turn while doing these movements.
    local facing = wb.cur_position.facing

    while true do
        -- We have to re-read the position every iteration, since in theory the
        -- position could be completely replaced and we would get a stale reference,
        -- thus all of the relative checks would fail.
        local position = wb.cur_position.position

        -- Easy case, can we just go?
        if helpers.can_stand_in(wb:blockQuery(helpers.getAdjacentBlock(position, facing, "f"))) then
            -- yeah, go forward
            -- Cancel if we cannot afford it
            if not shortcut_or_refuel(task) then return false end
            task_helpers.assert(wb:forwardScan())

            -- Bail if we found a block we want, don't even care where we end up
            if check_neighbors(task) then return true end

            -- Are we where we want to be?
            if back_moves <= 0 then
                -- No more backtracking to do, we'er done!
                -- Just to be sure... This should never change
                task_helpers.assert(facing == wb.cur_position.facing)
                return true
            end
            -- Still need to move forwards more, keep going
            back_moves = back_moves - 1
            last_move = "f"
            goto continue
        end

        -- Can we go up?
        -- Skip if we're on our way down already.
        if last_move ~= "d" then
            if helpers.can_stand_in(wb:blockQuery(helpers.getAdjacentBlock(position, facing, "u"))) then
                -- Cancel if we cannot afford it
                if not shortcut_or_refuel(task) then return false end
                task_helpers.assert(wb:upScan())
                if check_neighbors(task) then return true end
                last_move = "u"
                goto continue
            end
        end

        -- Ceiling hit or already descending, can we go back?
        if helpers.can_stand_in(wb:blockQuery(helpers.getAdjacentBlock(position, facing, "b"))) then
            -- Cancel if we cannot afford it
            if not shortcut_or_refuel(task) then return false end
            task_helpers.assert(wb:backScan())
            if check_neighbors(task) then return true end
            back_moves = back_moves + 1
            last_move = "b"
            goto continue
        end

        -- Shoot, can we go down?
        if helpers.can_stand_in(wb:blockQuery(helpers.getAdjacentBlock(position, facing, "d"))) then
            -- Cancel if we cannot afford it
            if not shortcut_or_refuel(task) then return false end
            task_helpers.assert(wb:downScan())
            if check_neighbors(task) then return true end
            last_move = "d"
            goto continue
        end


        -- There's actually nowhere to go, which is odd.
        -- This could happen if we managed to hit a dead end after turning into
        -- a tunnel (?) but i think this is unlikely anyways (?)
        if true then return false end

        ::continue::
    end
end


--- Searches the floor for a block, moving in a spiral.
---
--- Respects the fuel buffer set. Will only keep a fuel buffer that includes
--- returning to the starting position if return to start is set.
---
--- Takes in a TurtleTask. See BranchMinerData for the sub-config.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function block_search(config)
    local wb = config.walkback

    -- Reset found_block since lua loves caching stuff.
    found_block = nil

    -- Pre-checks.

    -- Right task?
    if config.definition.task_data.name ~= "block_search" then
        task_helpers.throw("bad config")
    end

    -- This must be the right task.
    local task_data = config.definition.task_data
    --- @cast task_data BlockSearchData

    -- Did we actually get something to look for?
    if #task_data.to_find.names_patterns == 0 and #task_data.to_find.tags == 0 then
        -- bruh
        task_helpers.throw("bad config")
    end

    --- Do we have enough fuel?
    if config.definition.fuel_buffer > wb:getFuelLevel() then
        task_helpers.throw("out of fuel")
    end

    -- I dont know how to do this with clever math, but the spiral pattern is
    -- 2, 3, 5, 6, 8, 9, 11, 12
    -- so its in pairs, and we either add 1 or 2 depending on parity

    -- How many steps we've done in the current line
    local line_steps = 0  -- how many steps taken in the current leg

    -- How many steps remain in the line
    local line_length = 2

    -- Alternates between true and false
    local parity = false

    -- Scan the blocks around us to make sure we have them documented before trying
    -- to look at them
    wb:spinScan()
    -- You never know, we might be right next to what we need.
    check_neighbors(config)

    while true do

        -- Check positions if needed
        if found_block == nil then
            check_neighbors(config)
        end

        -- Find something?
        if found_block ~= nil then
            -- Yay!
            break
        end

        -- Need to keep looking

        -- Done with the current line?
        if line_steps >= line_length then
            -- Turn right and begin the next line
            wb:turnRight()

            -- Increase the length and keep going
            if not parity then
                line_length = line_length + 1
                parity = true
            else
                line_length = line_length + 2
                parity = false
            end

            line_steps = 0
        end

        -- Have enough fuel?
        if not shortcut_or_refuel(config) then
            -- We cannot continue the spiral. We are done without finding
            -- anything :(
            break
        end

        -- Move forwards
        if not forward_step(config) then
            -- Ran out of fuel while moving forwards.
            break
        end

        -- Fall down if needed
        if not fall_down(config) then
            -- Ran out of fuel falling down.
            break
        end

        line_steps = line_steps + 1

    end

    -- We might have found something. Box it up in a nice little result
    --- @type BlockSearchResult
    local result = {
        name = "block_search_result",
        found = nil
    }

    -- apparently lua can cache locals... This might break stuff in other places
    -- i gotta go look now lmao
    if found_block ~= nil then
        result.found = helpers.clonePosition(found_block)
    end
    found_block = nil

    return task_helpers.try_finish_task(config, result)

end

return block_search