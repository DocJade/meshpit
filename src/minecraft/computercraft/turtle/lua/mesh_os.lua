-- The underlying operating system that the turtles will utilize.

-- =========
-- Notes
-- =========

-- Tasks are run sequentially. The OS will only ever run one sub-thread, and wait
-- for it to yield. We do not switch the current task, we only ever work on the
-- task at the end of the queue.

-- When tasks yield, they do not return anything in the `coroutine.yield()`,
-- all messages from tasks must be put into the event queue with a custom event.
--


-- =========
-- Imports
-- =========

--- This is NOT global, since we don't want tasks to pop walkbacks that a previous
--- task expects to still be there.
local walkback = require("walkback")
local panic = require("panic")
-- This defines its own global.
require("networking")

-- =========
-- Locals
-- =========

--- The stack of tasks being worked on.
--- First in first out, IE newest tasks are at the end of the list.
---@type TurtleTask[]
local task_queue = {}

--- Keep track if we are currently sleeping for a task. This is non-nill if
--- we are sleeping, and is set to the timestamp of when the task should be
--- resumed.
---@type number|nil
local currently_sleeping = nil

-- =========
-- Types
-- =========

--- This is the type used to store the state of a task.
--- @class TurtleTask
--- @field task_thread thread


--- The allowed strings to send from yielding.
--- @alias YieldStrings
--- | "" -- This call to yield is just for yielding, the task does not need anything.
--- | "unknown" -- TODO:

--- A type that holds every possible kind of event.
--- @alias CCEvent
--- | CCEventAlarm
--- | CCEventModemMessage
--- | CCEventPeripheral
--- | CCEventTimer
--- | CCEventTurtleInventory
--- | CCEventWebsocketClosed
--- | CCEventWebsocketMessage

--- A list of all of the string names of the events, this is used for linting.
--- @alias CCEventName
--- | "alarm"
-- --- | "char" -- Irrelevant, we wont be typing into turtles
-- --- | "computer_command" -- Irrelevant, we wont be queuing commands with the /computercraft commands
-- --- | "disk" -- Irrelevant, we wont ever be waiting for disk events.
-- --- | "disk_eject" -- Irrelevant, we wont ever be waiting for disk events.
-- --- | "file_transfer" -- Irrelevant, we will not be dragging and dropping files into computers.
-- --- | "http_check" -- Irrelevant, we only use blocking web methods, also we do not use HTTP
-- --- | "http_failure" -- Irrelevant, we do not use HTTP
-- --- | "http_success" -- Irrelevant, we do not use HTTP
-- --- | "key" -- Irrelevant, we wont be typing into turtles
-- --- | "key_up" -- Irrelevant, we wont be typing into turtles
--- | "modem_message"
-- --- | "monitor_resize" -- Irrelevant, we wont use monitors
-- --- | "monitor_touch" -- Irrelevant, we wont use monitors
-- --- | "mouse_click" -- Irrelevant, we wont be using the mouse in computers
-- --- | "mouse_drag" -- Irrelevant, we wont be using the mouse in computers
-- --- | "mouse_scroll" -- Irrelevant, we wont be using the mouse in computers
-- --- | "mouse_up" -- Irrelevant, we wont be using the mouse in computers
-- --- | "paste" -- Irrelevant, we wont be using the mouse in computers
--- | "peripheral"
--- | "peripheral_detach"
-- --- | "rednet_message" -- Irrelevant, we do not use rednet.
-- --- | "redstone" -- Irrelevant, we do not need to know about redstone updates.
-- --- | "speaker_audio_empty" -- Irrelevant, we do not use speakers
-- --- | "task_complete" -- Irrelevant, this is for when async events are called, we do not use these.
-- --- | "term_resize" -- Irrelevant, turtle terminals cannot be resized.
-- --- | "terminate" -- Irrelevant, we will never hold ctrl+T in a turtle. We also do not pullRaw.
--- | "timer"
--- | "turtle_inventory"
--- | "websocket_closed"
-- --- | "websocket_failure" -- Irrelevant, we only use blocking web methods
--- | "websocket_message"
-- --- | "websocket_success" -- Irrelevant, we only use blocking web methods

-- Computercraft event types. They are not defined in the CC:Tweaked extension
-- lints, so we need to re-list them here.

--- The alarm event is fired when an alarm started with os.setAlarm completes.
--- @class CCEventAlarm
--- @field [1] "alarm"
--- @field [2] number -- The ID of the alarm that finished.

--- The modem_message event is fired when a message is received on an open channel on any modem.
--- @class CCEventModemMessage
--- @field [1] "modem_message"
--- @field [2] number -- The ID of the alarm that finished.
--- @field [3] string -- The side of the modem that received the message.
--- @field [4] number -- The channel that the message was sent on.
--- @field [5] number -- The reply channel set by the sender.
--- @field [6] any -- The message as sent by the sender.
--- @field [7] number|nil -- The distance between the sender and the receiver in blocks, or nil if the message was sent between dimensions.

--- The peripheral event is fired when a peripheral is attached on a side or to a modem.
---
--- This also fires when you move into a position that's next to another turtle.
--- @class CCEventPeripheral
--- @field [1] "peripheral"
--- @field [2] string -- The side the peripheral was attached to.

--- The timer event is fired when a timer started with os.startTimer completes.
--- @class CCEventTimer
--- @field [1] "timer"
--- @field [2] string -- The ID of the timer that finished.

--- The turtle_inventory event is fired when a turtle's inventory is changed.
--- @class CCEventTurtleInventory
--- @field [1] "turtle_inventory"
--- no further info, its just that it has changed.

--- The websocket_closed event is fired when an open WebSocket connection is closed.
--- @class CCEventWebsocketClosed
--- @field [1] "websocket_closed"
--- @field [2] string -- The URL of the WebSocket that was closed.
--- @field [3] string|nil -- The server-provided reason the websocket was closed. This will be nil if the connection was closed abnormally.
--- @field [4] string|nil -- The connection close code, indicating why the socket was closed. This will be nil if the connection was closed abnormally.

--- The websocket_message event is fired when a message is received on an open WebSocket connection.
--- @class CCEventWebsocketMessage
--- @field [1] "websocket_message"
--- @field [2] string -- The URL of the WebSocket that was closed.
--- @field [3] string -- The contents of the message.
--- @field [4] boolean -- Whether this is a binary message.



-- Custom events
--- @alias CustomEvent
--- | CustomEventYield
--- | CustomEventSleep
--- | CustomEventSpawnTask

--- A yield to OS event. Can be safely discarded immediately.
---
--- We should never see this, since that would imply that we yielded to lua,
--- yet didn't immediately re-consume that yield.
--- @class CustomEventYield
--- @field [1] "yield"

--- This is a task telling the OS that it needs to sleep for some amount of time.
---
--- Setting a timer with an end date in the past has no effect. Thus don't do it.
---
--- The provided timestamp is in `utc`, and is unconverted (ie its in milliseconds)
--- @class CustomEventSleep
--- @field [1] "sleep"
--- @field [2] number -- Time to wake up. This should be a time offset from utc epoch.

--- Add a new task to the queue.
---
--- Tasks are allowed to spawn sub-tasks if needed. Thus there is a boolean to
--- mark it as such
---
--- Spawned sub-tasks will be initialized in the same way as normal tasks.
--- @class CustomEventSpawnTask
--- @field [1] "spawn_task"
--- @field [2] TaskDefinition
--- @field [3] boolean -- Wether this was spawned as a sub-task to the currently running task.


-- =========
-- Task functions
-- =========

--- Requests new tasks. Adds all of the new tasks to the queue and returns the
--- last one.
---
--- This will always return a task, it may be a wait task if there is nothing to do.
--- @return TurtleTask
local function request_new_tasks()
    -- Currently does nothing.
end

--- Set a timer for one second and sleep for it.
---
--- We only sleep for one second at a time, as we still want to wake up and handle
--- other events regardless if the current task is running. This delay may be
--- increased in the future if needed.
local function second_sleep()
    -- unlike the usual os.sleep, we are not discarding events.
    -- The normal os.sleep() really strangely just sits in a tight loop, throwing
    -- away timer events until it hits the timer it's looking for??? Very strange.
    -- https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/core/src/main/resources/data/computercraft/lua/bios.lua#L49-L56

    ---@diagnostic disable-next-line: undefined-field
    local timer_id = os.startTimer(1)

    -- However, this does mean that if we get a timer that is NOT the one we are
    -- looking for, we have to put it back into the pile.
    -- Since this timer only runs for one second and this constantly yields due
    -- to waiting for events, thats fine...
    local timer_string = "timer"
    while true do
        ---@diagnostic disable-next-line: undefined-field
        local event = os.pullEvent(timer_string)
        if event.number == timer_id then break end
        -- This is not the right timer.
        ---@diagnostic disable-next-line: undefined-field
        os.queueEvent(timer_string, event.number)
    end
end

-- =========
-- Event handling
-- =========

--- Handle all events from the os queue. This assumes that the yield events have
--- already been dealt with.
local function handle_events()
    while true do
        ---@type CCEvent|CustomEvent
        ---@diagnostic disable-next-line: undefined-field
        local event = os.pullEvent()
        local event_name = event[1]
        if event_name == "yield" then
            -- We should never see this
            panic.panic("Dangling yield!")
        elseif event_name == "sleep" then
            -- The task wants to sleep. Set up the sleeping mode.
            ---@cast event CustomEventSleep
            currently_sleeping = event[2]
            -- we still finish checking the rest of the events, the
            -- sleeping happens on the next iteration of the main loop.
        elseif event_name == "alarm" then
            -- TODO: Do something with this event
        elseif event_name == "modem_message" then
            -- TODO: Do something with this event
        elseif event_name == "peripheral" then
            -- TODO: Do something with this event
        elseif event_name == "timer" then
            -- TODO: Do something with this event
        elseif event_name == "turtle_inventory" then
            -- TODO: Do something with this event
        elseif event_name == "websocket_closed" then
            -- TODO: Do something with this event
        elseif event_name == "websocket_message" then
            -- TODO: Do something with this event
        else
            -- This is an event we do not care about
            -- Thus we do nothing.
        end
    end
end

-- =========
-- Startup
-- =========

--- Things that need to be done before entering the main loop for the first time.
---
--- Does not call the main loop after startup finishes.
function startup()
    -- Set up networking
    -- TODO: move connect() in networking to a public thing.
end

-- =========
-- Main loop
-- =========

--- This is the main loop of the operating system.
--- This will never return.
---
--- This loop needs to be hyper-optimized to minimize the time it takes to
--- continue running a task.
function main()
    -- Bring in locals to make yielding slightly faster.

    -- Queue event function
    ---@type function
    ---@diagnostic disable-next-line: undefined-field
    local queue = _G.os.queueEvent

    -- Yield function, directly yields to the lua engine
    local yield = _G.coroutine.yield

    -- Resume coroutines
    local resume = _G.coroutine.resume

    -- Resume coroutines
    local status = _G.coroutine.status

    -- The empty string we pass to the yield, since we aren't actually yielding
    -- for any real reason, we need to push an event to the event queue, otherwise
    -- the OS would not resume until some other event happens.
    local yield_string = "yield"

    while true do
        -- Yield to the Lua engine, this means we yield twice per loop, but
        -- in-case the task request stuff breaks and there is nothing to
        queue(yield_string)

        -- Instead of blindly taking the next event, we always search for yield
        -- to prevent consuming other kinds of events.
        yield(yield_string)

        -- Are we sleeping?
        if currently_sleeping then
            -- Are we done sleeping?
            ---@diagnostic disable-next-line: undefined-field
            if os.epoch("utc") >= currently_sleeping then
                -- All done!
                currently_sleeping = nil
            else
                -- We are still sleeping. Sleep for a second, then skip
                -- straight to handling events.
                second_sleep()
                goto skip_task
            end
        end

        -- Grab a task from the queue, unless it is empty.
        --- @type TurtleTask?
        local task = task_queue[#task_queue]

        -- If there is no task, get new tasks.
        if not task then
            task = request_new_tasks()
            -- Double check
            panic.assert(task ~= nil, "Received no new tasks!")
        end

        -- Run the current task.
        ---@type boolean, TaskCompletion|TaskFailure
        local bool, result = resume(task.task_thread)

        -- Is the task over?
        if not bool then
            -- The task has ended. This either indicates that it actually
            -- finished, or that the the task threw an error.

            -- Did the task throw an error?
            -- TODO: Handle task throws.


            -- TODO: We have no need to check what kind of task end it was.
            -- Done running that task, so we remove it from the queue and loop!
            task_queue[#task_queue] = nil
            break
        end

        -- This label is used when we are sleeping, as to not wake up the task
        -- while it is eeping ever so peacefully.
        ::skip_task::

        -- Handle events
        handle_events()

        -- Keep going!
    end
end