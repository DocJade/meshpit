--- Helpers for tasks.
local test_helpers = {}



--- Assert something as true.
---
--- Throws a task failure if this is not the case.
---
--- Does not allow passing a message in the traceback. Instead, you should comment
--- on the line above the throw why you are asserting.
--- @param assertion boolean
function test_helpers.assert(assertion)
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
function test_helpers.throw(reason)
    ---@type TaskFailure
    local task_failure = {
        kind = "fail",
        reason = reason,
        stacktrace = debug.traceback(nil, 2)
    }
    error(task_failure, 0)
end

--- Move all of the items in the inventory towards the end, freeing up slots in
--- the front.
---
--- Takes in a list of slots to ignore moving from. However items can still be
--- moved _into_ these slots if they are empty.
--- @param ignored_slots number[]?
function test_helpers.pushInventoryBack(ignored_slots)
    -- Map out what slots are used

end

return test_helpers