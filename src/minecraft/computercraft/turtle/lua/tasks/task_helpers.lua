--- Helpers for tasks.
local task_helpers = {}

--- We also use the other helpers to help our helper. Yeah.
local helpers = require("helpers")

--- Queue a event. This is a wrapper around the inner computercraft call, as
--- it doesn't have the type hinting that we want. You can only queue the
--- custom events that the OS adds.
---
--- This is meant to be a private method, tasks are not to queue events themselves.
---@param event CustomEvent
local function taskQueueEvent(event)
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent(table.unpack(event))
end

--- Attempt to spawn a sub-task from the current task.
---
--- This will yield the current task until the sub-task completes.
---
--- Returns a boolean and the result of the sub-task, if any.
---
--- Returns `false` if the subtask was unable to be spawned for any reason.
--- @param current_task TurtleTask -- The currently running task.
--- @param subtask TaskDefinition
--- @return boolean, TaskCompletion|TaskFailure|"impossible config"
function task_helpers.spawnSubTask(current_task, subtask)
    -- Sub-tasks are easy to spawn, but we do need to meet the requirements the
    -- definition sets, otherwise adding the task would immediately fail.

    -- Is the fuel buffer for the sub-task
    if subtask.fuel_buffer > current_task.walkback:getFuelLevel() then
        -- Impossible.
        return false, "impossible config"
    end

    -- Spawn the task.
    -- `true` Marks this as a sub-task.
    ---@type CustomEventSpawnTask
    local sub_task = {"spawn_task", subtask, true}

    taskQueueEvent(sub_task)

    -- Yield to the OS.
    task_helpers.taskYield()

    -- If we're back here, the sub task is done!
    -- Retrieve the sub-task's result.

    -- We immediately snipe it out of the TurtleTask, since the value stored
    -- is only meant to be returned here. That's its only purpose. It doesn't
    -- even pass butter.

    local sub_task_result = current_task.last_subtask_result
    -- We expect to always get SOME kind of result.
    --- @cast sub_task_result TaskCompletion|TaskFailure
    current_task.last_subtask_result = nil
    return true, sub_task_result
end

--- Assert something as true.
---
--- Throws a task failure if this is not the case.
---
--- Does not allow passing a message in the traceback. Instead, you should comment
--- on the line above the throw why you are asserting.
--- @param assertion boolean
function task_helpers.assert(assertion)
    if assertion then return end
    -- Assertion failed.
    ---@type TaskFailure
    local assertion_failure = {
        kind = "fail",
        reason = "assertion failed",
        stacktrace = debug.traceback(nil, 2)
    }
    error(assertion_failure, 0)
end

--- Easily throw a task failure of a specific kind.
---
--- Does not allow passing a message in the traceback. Instead, you should comment
--- on the line above the throw why you are throwing.
--- @param reason TaskFailureReason
function task_helpers.throw(reason)
    ---@diagnostic disable-next-line: undefined-field
    -- os.setComputerLabel("task threw! " .. reason)
    ---@type TaskFailure
    local task_failure = {
        kind = "fail",
        reason = reason,
        stacktrace = debug.traceback(nil, 2)
    }
    -- Doing a throw here stops the subroutine immediately without needing to
    -- propagate this value upwards.
    error(task_failure, 0)
end

--- Completely yield this task for a number of seconds.
---
--- Calling this will yield the task automatically, and the task will not resume
--- until at least the specified amount of seconds has passed.
---
--- Please take care to not sleep for too long, IE do not use this to block your
--- task forever, and be very sure to not pass in values that you've calculated
--- from other values without ensuring its not too long.
--- @param seconds number
function task_helpers.taskSleep(seconds)
    -- Calculate the walkup time.
    -- Convert from real seconds to in-game seconds.
    local seconds = helpers.realSecondsToInGameSeconds(seconds * 1000)

    ---@diagnostic disable-next-line: undefined-field
    local wake_time = os.epoch() + seconds

    -- Queue the event, and yield.
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent("sleep", wake_time)
    task_helpers.taskYield()
end


--- Yield the task to the OS.
---
--- The task will be resumed as soon as the OS finishes doing its maintenance tasks.
---
--- Theoretically the task could never be resumed again / deleted, however you
--- do not need to worry about that, as the OS will clean up in that case.
function task_helpers.taskYield()
    -- This seems like a pointless wrapper, but maybe we will do more here later.
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent("yield")
    coroutine.yield("yield")
end

--- Move all of the items in the inventory towards the end, freeing up slots in
--- the front.
---
--- Preserves ordering of items, assuming nothing is marked as ignored. If items
--- are ignored, they will be "Jumped" over. IE:
---  1, [2], _, 3
---  _, [2], 1, 3
---
--- Requires a reference to walkback to do inventory movement.
---
--- Takes in a list of slots to ignore moving from. However items can still be
--- moved _into_ these slots if they are empty.
---
--- Will free up as many slots as possible starting at position 1 going upwards.
--- Does not combine stacks of the same item, as we only check if a slot is full
--- or empty.
--- @param walkback WalkbackSelf
--- @param ignored_slots number[]?
function task_helpers.pushInventoryBack(walkback, ignored_slots)
    -- Keep track of which slots to skip
    ---@type boolean[]
    local ignore_map = {}
    -- Ignored slots are true.
    for _, slot in ipairs(ignored_slots or {}) do
        ignore_map[slot] = true
    end

    -- Start from the back, pulling items upwards. Preserves order of items too!
    -- Yes this checks slots a lot but non-detailed information is fast.
    -- Like, REALLY fast, over a million times per second fast. lol.

    -- I really wish lua had continues.
    for i = 16, 1, -1 do
        if walkback:getItemDetail(i) ~= nil then goto continue end
        -- Slot is empty, try moving stuff up.
        for j = i - 1, 1, -1  do
            -- Skip ignored slots, and check for items in this slot
            if not ignore_map[j] and walkback:getItemDetail(j) ~= nil then
                -- No need to check the result since we know this slot is empty.
                walkback:transferFromSlotTo(j, i)
                break
            end
        end
        ::continue::
    end
end

--- Finish a task. Assumes you have not popped any walkback state, or have already
--- properly put it back on.
---
--- Things you should check before calling this:
--- - You have enough fuel to do the current walkback if needed.
---
--- !! This will throw if the finish requirements cannot be met. !!
---
--- Returns a boolean TaskCompletion pair. If the task cannot be completed due
--- to some unmet constraint, then this will return false.
---
---@param turtle_task TurtleTask
---@param result_data TaskResultData
---@return TaskCompletion
function task_helpers.tryFinishTask(turtle_task, result_data)
    -- Run walkback if needed.
    local backoff_delay = 1
    if turtle_task.definition.return_to_start then
        -- Is there any walkback to do?
        local cost = turtle_task.walkback:cost()

        -- Skip if zero
        if cost == 0 then goto walkback_done end

        -- Check if we can make it back
        if cost > turtle_task.walkback:getFuelLevel() - turtle_task.definition.fuel_buffer then
            -- Don't have enough fuel to do the walkback:
            task_helpers.throw("out of fuel")
        end

        -- Do the walkback
        while true do
            -- We try several times just in case something moved in the way
            -- such as a another turtle. We will exponentially back off.
            local walkback_result, fail_message = turtle_task.walkback:rewind()
            if walkback_result then
                -- Done!
                break
            end

            -- That didn't work. We will retry.
            if backoff_delay > 32 then
                -- Out of attempts
                task_helpers.throw("walkback rewind failure")
            end
            task_helpers.taskSleep(backoff_delay)
            -- Double it for the next run
            backoff_delay = backoff_delay * 2
        end

        -- Double check that we ended where we started. This should be the case
        -- unless the task popped off a walkback and didn't put it back.
        local current_position = turtle_task.walkback.cur_position.position
        task_helpers.assert(helpers.coordinatesAreEqual(current_position, turtle_task.start_position))
    end
    ::walkback_done::

    -- Rotate to the correct facing position if needed.
    if turtle_task.definition.return_to_facing then
        -- Rotate that way
        -- This cannot fail.
        turtle_task.walkback:turnToFace(turtle_task.start_facing)
        task_helpers.assert(turtle_task.walkback.cur_position.facing == turtle_task.start_facing)
    end

    -- All good.
    ---@type TaskCompletion
    return {kind = "success", result = result_data}
end

--- Attempt to burn a single item as fuel from the turtle's inventory based
--- on string patterns. These patterns only match names. Be careful to not use
--- patterns that are too broad.
---
--- May spawn a crafting task to make planks.
---
--- Iterates the inventory front to back for items to burn, after finding a match,
--- one item from that matching slot will be consumed as fuel.
---
--- Preserves what inventory slot was selected before the call.
---
--- Returns true if an item was burnt.
--- @param wb WalkbackSelf
--- @param fuel_patterns string[]
--- @return boolean
function task_helpers.tryRefuelFromInventory(wb, fuel_patterns)
    -- Can't burn no options!
    if #fuel_patterns == 0 then return false end

    local original_slot = wb:getSelectedSlot()

    -- Front to back since when mining those are the stacks added to first.
    for i = 1, 16 do
        local item = wb:getItemDetail(i)
        -- Skip empty slots
        if not item then goto continue end

        -- Check if the item matches any pattern
        for _, pattern in pairs(fuel_patterns) do
            if not helpers.findString(item.name, pattern) then goto bad_pattern end
            local select_me = i
            local amount_to_burn = 1

            -- Good item.
            -- If this is a log, we should craft it into planks first before
            -- burning it. This quadruples their fuel value.
            -- TODO: Is there a nicer way we can factor this? This feels like a
            -- weird place to put this.
            if helpers.findString(pattern, "log") then
                -- Log. Can we craft it down?
                -- Need: Room for chest, a chest, and room in our inventory (with safety margin).
                -- Need the chest as we don't wanna accidentally craft mid-air and drop stuff.
                if (not wb:detectDown()) and
                        wb:countEmptySlots() >= 3 and
                        wb:inventoryCountPattern("chest") > 0
                    then
                    -- We can plank it.
                    --- @type TaskDefinition
                    local makie_da_plankie = {
                        fuel_buffer = 0,
                        return_to_facing = true,
                        return_to_start = true,
                        --- @type CraftingData
                        task_data = {
                            name = "craft_task",
                            count = 1,
                            recipe = {
                                shape = {
                                    "log",   "BLANK", "BLANK",
                                    "BLANK", "BLANK", "BLANK",
                                    "BLANK", "BLANK", "BLANK"
                                }
                            }
                        }
                    }

                    -- Since we may not be inside of a task, we need to just spawn the task
                    -- normally. This is disgusting, but I have no idea how to factor
                    -- this better right now.
                    -- We cannot mark this as a sub task, as we may not be currently within a task.
                    -- Thus we get no result from running this. We will just have to
                    -- count the plank delta to see if it worked.

                    local pre_craft_planks = wb:inventoryCountPattern("planks")

                    ---@type CustomEventSpawnTask
                    local sub_task = {"spawn_task", makie_da_plankie, false}

                    taskQueueEvent(sub_task)

                    -- Yield to the OS to run the new task. lol.
                    task_helpers.taskYield()

                    local worked = pre_craft_planks < wb:inventoryCountPattern("planks")
                    -- This should always work, but if it didn't, then we will just not change the slot to eat
                    if worked then
                        -- Find the planks
                        local plank_slot = wb:inventoryFindPattern("planks")
                        -- This should exist.
                        task_helpers.assert(plank_slot ~= nil)
                        --- @cast plank_slot number
                        -- Make sure there are 4 planks in that slot to burn
                        if wb:getItemCount(plank_slot) >= 4 then
                            -- Tell the next section to select and burn all 4.
                            select_me = plank_slot
                            amount_to_burn = 4
                        end
                    end
                end
            end

            -- Burn it.
            wb:select(select_me)
            local did_refuel = wb:refuel(amount_to_burn)
            wb:select(original_slot)

            -- Did that work?
            if did_refuel then return true end

            ::bad_pattern::
        end
        ::continue::
    end

    -- Just in case...
    wb:select(original_slot)
    return false
end

--- Attempt to compact the inventory by consolidating items.
---
--- Returns true if any slots were freed up from compaction
--- @param wb WalkbackSelf
--- @return boolean
function task_helpers.compactInventory(wb)
    -- Loop over the slots, looking for partial stacks
    --- @type {count: number, name: string, slot: number}[]
    local partial_stacks = {}
    local old_free_slots = wb:countEmptySlots()
    for slot = 1, 16 do
        local count = wb:getItemCount(slot)
        -- Check if the stack can hold more items, and that the stack is not empty.
        -- We check if we can actually hold more items in the stack directly since
        -- we need to handle un-stackable items.

        if (count ~= 0) and (wb:getItemSpace(slot) > 0) then
            -- Partial stack that can hold more items. Worth tracking.
            local item = wb:getItemDetail(slot)
            -- This has to have something in it.
            --- @cast item Item
            local name = item.name
            partial_stacks[#partial_stacks+1] = {
                count = count,
                name = name,
                slot = slot
            }
        end
    end

    -- Is there anything to compact?
    if #partial_stacks == 0 then
        -- Nothing we can do
        return false
    end

    -- Sort the array to put the biggest stacks first
    table.sort(partial_stacks, function (a, b)
        -- Group by name first, then by count descending
        if a.name ~= b.name then return a.name < b.name end
        return a.count > b.count
    end)

    -- Merge adjacent same-name stacks
    local index = 1
    while index < #partial_stacks do
        local range_end = index + 1
        -- Find the range in the array where the names are the same and need to be merged
        while range_end <= #partial_stacks and partial_stacks[range_end].name == partial_stacks[index].name do
            range_end = range_end + 1
        end
        -- Now [index, range_end - 1] have to have the same name. Which could just
        -- be one item, but that would be immediately skipped by the while condition.
        -- Merge items from back to front
        local low, high = index, range_end - 1
        while low < high do
            wb:select(partial_stacks[high].slot)
            wb:transferTo(partial_stacks[low].slot)
            -- Now if the slot is full, we move to the next slot to move items
            -- into.
            if wb:getItemSpace(partial_stacks[low].slot) == 0 then
                low = low + 1
            end
            -- If the stack we were pulling from is now empty, move back to the
            -- next stack.
            if wb:getItemCount(partial_stacks[high].slot) == 0 then
                high = high - 1
            end
        end
        index = range_end
    end

    -- Now count up how many items changed and see if we actually made more room.
    local made_room = old_free_slots < wb:countEmptySlots()
    -- If we didn't make room, we're immediately done.
    if not made_room then
        return false
    else
        -- We improved the inventory for sure, but we can run the compaction again
        -- since the compaction may have made new partial slots to re-compact again.
        task_helpers.compactInventory(wb)
    end
    -- We must have made room at this point!
    return true
end

--- Helper function to check that we still have an empty inventory slot, or
--- discard items if we need to free up slots.
---
--- Returns a boolean on wether or not the task can continue.
--- @param wb WalkbackSelf
--- @param discardables DiscardableItems
--- @return boolean
function task_helpers.inventoryCheck(wb, discardables)
    -- If there's a free slot, nothing to do.
    if wb:haveEmptySlot() then return true end

    -- Try compacting the inventory before discarding stuff
    if task_helpers.compactInventory(wb) then
        -- That made room.
        return true
    end

    local slot_to_discard = nil

    -- Need to discard something.
    for _, pattern in ipairs(discardables.patterns) do
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


return task_helpers