--- Helpers for tasks.
local task_helpers = {}

--- We also use the other helpers to help our helper. Yeah.
local helpers = require("helpers")

--- Attempt to spawn a sub-task from the current task.
---
--- This will yield the current task until the sub-task completes.
---
--- Returns `false` if the subtask was unable to be spawned for any reason.
--- @param current_task TurtleTask -- The currently running task.
--- @param subtask TaskDefinition
function task_helpers.spawnSubTask(current_task, subtask)
    -- Sub-tasks are easy to spawn, but we do need to meet the requirements the
    -- definition sets, otherwise adding the task would immediately fail.

    -- Is the fuel buffer for the sub-task
    if subtask.fuel_buffer > current_task.walkback.getFuelLevel() then
        -- Impossible.
        return false
    end

    -- Spawn the task.
    -- `true` Marks this as a sub-task.
    ---@type CustomEventSpawnTask
    local sub_task = {"spawn_task", subtask, true}

    taskQueueEvent(sub_task)

    -- Yield to the OS.
    task_helpers.taskYield()

    -- If we're back here, the sub task is done!
    return true
end

--- Queue a event. This is a wrapper around the inner computercraft call, as
--- it doesn't have the type hinting that we want. You can only queue the
--- custom events that the OS adds.
---
--- This is meant to be a private method, tasks are not to queue events themselves.
---@param event CustomEvent
function taskQueueEvent(event)
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent(table.unpack(event))
end

--- Assert something as true.
---
--- Throws a task failure if this is not the case.
---
--- Does not allow passing a message in the traceback. Instead, you should comment
--- on the line above the throw why you are asserting.
--- @param assertion boolean
function task_helpers.assert(assertion)
    -- Might as well yield in here too.
    task_helpers.taskYield()
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
    ---@type TaskFailure
    local task_failure = {
        kind = "fail",
        reason = reason,
        stacktrace = debug.traceback(nil, 2)
    }
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
    ---@diagnostic disable-next-line: undefined-field
    local wakeup_time = os.epoch("utc") + (seconds * 1000)

    -- Queue the event, and yield.
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent("sleep", wakeup_time)
end


--- Yield the task to the OS.
---
--- The task will be resumed as soon as the OS finishes doing its maintenance tasks.
---
--- Theoretically the task could never be resumed again / deleted, however you
--- do not need to worry about that, as the OS will clean up in that case.
function task_helpers.taskYield()
    -- This seems like a pointless wrapper, but maybe we will do more here later.
    coroutine.yield()
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
        if walkback.getItemDetail(i) ~= nil then goto continue end
        -- Slot is empty, try moving stuff up.
        for j = i - 1, 1, -1  do
            -- Might as well yield the task in here
            task_helpers.taskYield()

            -- Skip ignored slots, and check for items in this slot
            if not ignore_map[j] and walkback.getItemDetail(j) ~= nil then
                -- No need to check the result since we know this slot is empty.
                walkback.transferFromSlotTo(j, i)
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
--- to some un-met constraint, then this will return false.
---
---@param turtle_task TurtleTask
---@return TaskCompletion
function task_helpers.try_finish_task(turtle_task)
    -- Run walkback if needed.
    if turtle_task.definition.return_to_start then
        -- Is there any walkback to do?
        local cost = turtle_task.walkback.cost()

        -- Skip if zero
        if cost == 0 then goto walkback_done end

        -- Check if we can make it back
        if cost > turtle_task.walkback.getFuelLevel() - turtle_task.definition.fuel_buffer then
            -- Don't have enough fuel to do the walkback.
            task_helpers.throw("out of fuel")
        end

        -- Do the walkback
        -- TODO: Retry the walkback after some delay.
        local walkback_result, fail_message = turtle_task.walkback.rewind()
        if not walkback_result then
            task_helpers.throw("walkback rewind failure")
        end

        -- Double check that we ended where we started. This should be the case
        -- unless the task popped off a walkback and didn't put it back.
        local current_position = turtle_task.walkback.cur_position.position
        task_helpers.assert(helpers.coordinatesAreEqual(current_position, turtle_task.start_position))
    end
    ::walkback_done::

    -- Rotate to the correct facing position if needed.
    if task_config.definition.return_to_facing then
        -- Rotate that way
        -- This cannot fail.
        task_config.walkback.turnToFace(task_config.start_facing)
    end

    -- All good.
    ---@type TaskCompletion
    return {kind = "success"}
end

return task_helpers