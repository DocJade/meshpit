-- The underlying operating system that the turtles will utilize.

-- The OS does not start automatically. You must call the `startup()` function.
-- If testing the turtle, you can add tasks to the queue before calling `main`

local mesh_os = {}

local function hook(event, line)
    local s = debug.getinfo(2).short_src
    print(s .. ":" .. line)
end



-- =========
-- Notes
-- =========

-- Tasks are run sequentially. The OS will only ever run one sub-thread, and wait
-- for it to yield. We do not switch the current task, we only ever work on the
-- task at the end of the queue.

-- When tasks yield, they do not return anything in the `coroutine.yield()`,
-- all messages from tasks must be put into the event queue with a custom event.

-- =========
-- Imports
-- =========

--- This is NOT global, since we don't want tasks to pop walkbacks that a previous
--- task expects to still be there.
local walkback = require("walkback")
local panic = require("panic")
local helpers = require("helpers")
-- This defines its own global.
require("networking")

-- import all the task functions
local tree_chop_function = require("tree_chop")
local recursive_miner_function = require("recursive_miner")

-- Bring globals into scope to make them faster
---@type function
---@diagnostic disable-next-line: undefined-field
local queueEvent = os.queueEvent
---@type function
---@diagnostic disable-next-line: undefined-field
local epochFunction = os.epoch

-- Resume coroutines
local resume = _G.coroutine.resume

-- =========
-- Locals
-- =========

--- The stack of tasks being worked on.
--- First in first out, IE newest tasks are at the end of the list.
---@type TurtleTask[]
local task_queue = {}

-- The stack of popped walkbacks. This will always be 1 shorter than the
-- task_queue
---@type PoppedWalkback[]
local walkback_queue = {}

--- Track when we want to wake up from sleeping.
---
--- Expressed as a UTC timestamp.
--- @type number|nil
local wake_up_time = nil

--- Keep track if we are currently sleeping for a task. This is non-nill if
--- we are sleeping, and is set to the id of the timer we are sleeping for.
---@type number|nil
local sleeping_timer_id = nil

--- This is set when we are in test mode. Used for controlling some behavior
--- to not trigger in tests.
--- @type boolean
local test_mode = false

--- The default timer resolution to use when not sleeping. This can be changed
--- by the server if it thinks we are idle for too long, or it knows that we
--- won't get any new tasks / events for a while.
---
--- Expressed as seconds, including decimals.
--- @type number
local default_event_timer_resolution = 0.10

--- The maximum allowed timer resolution to prevent sleeping from making the
--- OS too unresponsive.
---
--- Do not modify this value. Defaults to 10 seconds.
--- @type number
local max_event_timer_resolution = 10


--- The current resolution of the task queue timer. This is increased automatically
--- when we are sleeping, and decreased back to the default when we wake up.
---
--- Sleeping will increase this to 1 second, or higher if needed.
---@type number
local current_event_timer_resolution = default_event_timer_resolution

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
--- @field [2] number -- Time to wake up. This should be an epoch time that has already been offset but the amount you wish to sleep for.

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
    -- If we are in test mode, we will throw an error to completely exit the OS
    -- giving us a path back to the startup script.
    ---@diagnostic disable-next-line: undefined-field
    if test_mode then error("request_new_tasks") end

    -- Currently does nothing.
    -- TODO: Default tasks!
    ---@diagnostic disable-next-line: undefined-field, missing-return
    os.shutdown()
end

--- Sets up an incoming task. TODO: We assume that this is valid right now,
--- maybe some day this will be safer lmao
--- @param task_definition TaskDefinition
--- @param is_sub_task boolean
local function setupNewTask(task_definition, is_sub_task)

    -- Pop our current walkback into the queue.
    -- It's fine to do nothing if there is no current walkback.
    ---@type PoppedWalkback|nil
    local popped = walkback:pop()
    if popped ~= nil then
        walkback_queue[#walkback_queue+1] = popped
    end

    -- The rest of the owl.
    ---@type TurtleTask
    local new_task = {
        definition = task_definition,
        start_facing = walkback.cur_position.facing,
        start_position = helpers.clonePosition(walkback.cur_position.position),
        ---@diagnostic disable-next-line: undefined-field
        start_time = os.epoch("utc"),
        -- TODO: See below todo lol
        ---@diagnostic disable-next-line: assign-type-mismatch
        task_thread = nil,
        walkback = walkback
    }

    -- Create the task and make the thread. Do not start it yet.
    -- Get the task function
    local task_function = getTaskFunction(task_definition.task_data)
    -- Wrap it in ANOTHER function which passes its arguments
    local the_cooler_function = function ()
        task_function(new_task)
    end

    local new_thread = coroutine.create(the_cooler_function)
    -- debug.sethook(new_thread, hook, "l")

    -- Then add the thread
    -- TODO: move the thread out of TurtleTask
    new_task.task_thread = new_thread

    -- Add task to the end of the task queue.
    task_queue[#task_queue+1] = new_task
end

--- !!! THIS IS ONLY FOR TEST CASES! !!!
---
--- Directly spawn a task. Setup must have been ran to have a proper walkback
--- state, but the OS does not need to be running.
--- @param task_definition TaskDefinition
function mesh_os.testAddTask(task_definition)
    -- We are officially testing
    test_mode = true

    -- Add the task.
    setupNewTask(task_definition, false)
end

--- Get the function associated with a task data
--- @param data TaskDataType
--- @return function
function getTaskFunction(data)
    local name = data.name
    if name == "tree_chop" then
        return tree_chop_function
    elseif name =="recursive_miner" then
        return recursive_miner_function
    end
    --????? None of those matched?
    panic.panic("Unknown task!")
    -- This is unreachable.
    ---@diagnostic disable-next-line: return-type-mismatch
    return nil
end

--- Set a timer for one second and sleep for it.
---
--- We only sleep for one second at a time, as we still want to wake up and handle
--- other events regardless if the current task is running. This delay may be
--- increased in the future if needed.
--- @param seconds number -- The number of seconds to sleep for. Can be fractional.
function os_sleep(seconds)

    -- TODO: This somehow the old timer ID is not being cleaned up properly

    -- unlike the usual os.sleep, we are not discarding events.
    -- The normal os.sleep() really strangely just sits in a tight loop, throwing
    -- away timer events until it hits the timer it's looking for??? Very strange.
    -- https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/core/src/main/resources/data/computercraft/lua/bios.lua#L49-L56

    -- We start our own timer, and put it into the event queue.
    -- But only if we don't already have a timer.
    if sleeping_timer_id ~= nil then return end

    -- print("Creating new sleep timer.")

    -- Reel in the sleep duration if its too short.
    seconds = math.max(seconds, default_event_timer_resolution)

    ---@diagnostic disable-next-line: undefined-field
    sleeping_timer_id = os.startTimer(seconds)

    -- Now, the event handler will grab the timer automatically and call
    -- `timer_cleanup` afterwards to stop sleeping.

    -- But before that, we will also need to increase the event timer resolution
    -- so we don't wake up more than we need to.
    current_event_timer_resolution = math.min(math.max(default_event_timer_resolution, seconds / 2), max_event_timer_resolution)
end


--- Handle timer events. This is also used to finish sleeping and reset the
--- event resolution after sleeping.
--- @param timer_id number
local function handle_timer_event(timer_id)
    -- Are we sleeping? And is this our wake-up call?
    if sleeping_timer_id ~= nil and timer_id == sleeping_timer_id then
        -- Our sleep has ended.
        sleeping_timer_id = nil
        -- Reset the event timer.
        current_event_timer_resolution = default_event_timer_resolution
        return
    end
    -- This wasn't the sleep timer. Honestly we shouldn't be using timers for
    -- anything besides OS sleeping, so we will freak out otherwise.

    -- TODO: Old timers are lingering after we have finished a sleep, resulting
    -- in a timer with an ID one below the current timer going off, causing failure.
    -- for now, we will just ignore any timer event that is not our sleep timer.

    -- ^^^^^^ This almost looks like its trying to sleep twice per sleep?

    return
    -- print("timer_id: ", timer_id)
    -- print("sleeping_timer_id: ", sleeping_timer_id)
    -- print("current_event_timer_resolution: ", current_event_timer_resolution)
    -- print("default_event_timer_resolution: ", default_event_timer_resolution)
    -- while true do end
    -- panic.panic("Unknown timer!")
end

-- =========
-- Event handling
-- =========

-- Keep track if we've seen the same event several times in a row to prevent
-- lockups.

--- We only handle one event at a time, as looping would require to always wait
--- for a timer to complete. The timer is only a backup to prevent being stuck
--- if the queue is actually empty.
local function handle_events()

    -- TODO: Make this pull events and put them into buckets based on event name
    -- so events can be pulled safely later, and we wont have to re-push events
    -- to the queue causing them to be re-read over and over when sleeping, causing
    -- wake-ups hundreds of times per second.




    -- Create the watchdog timer, just in case.
    -- We use the global timer resolution here.
    --- @diagnostic disable-next-line: undefined-field
    local watchdog = os.startTimer(current_event_timer_resolution)

    ---@type CCEvent|CustomEvent
    ---@diagnostic disable-next-line: undefined-field
    local event = table.pack(os.pullEvent())
    local event_name = event[1]
    print("Handling event: ", event_name)
    local handled_event = true
    -- print(event_name)
    if event_name == "turtle_response" then
        -- This is an internal CC:Tweaked event that we are able to see for
        -- some stupid reason, we need to put it back onto the queue now.
        queueEvent(table.unpack(event))
    elseif event_name == "yield" then
        -- We can eat this immediately, since we can just pass the string back
        -- to the task again later when it requests it.
    elseif event_name == "sleep" then
        -- The task wants to sleep. Set up the sleeping mode.
        ---@cast event CustomEventSleep
        wake_up_time = event[2]
    elseif event_name == "spawn_task" then
        -- Add a new task to the queue!
        ---@cast event CustomEventSpawnTask
        local task_definition = event[2]
        local is_sub_task = event[3]
        setupNewTask(task_definition, is_sub_task)
    elseif event_name == "alarm" then
        -- TODO: Do something with this event
    elseif event_name == "modem_message" then
        -- TODO: Do something with this event
    elseif event_name == "peripheral" then
        -- TODO: Do something with this event
    elseif event_name == "timer" then
        local timer_id = event[2]
        -- This must be a number
        ---@cast timer_id number
        -- Is this the watchdog?
        if timer_id == watchdog then
                -- There were no events at all. :(
            return
        end

        -- Not the watchdog, handle it normally.
        handle_timer_event(timer_id)

    elseif event_name == "turtle_inventory" then
        -- TODO: Do something with this event
    elseif event_name == "websocket_closed" then
        -- TODO: Do something with this event
    elseif event_name == "websocket_message" then
        -- TODO: Do something with this event
    else
        -- This is an event we do not care (or know) about
        -- Thus we do nothing.
        print("Saw unknown event:")
        print(event_name)
    end

    -- Cancel the watchdog.
    ---@diagnostic disable-next-line: undefined-field
    os.cancelTimer(watchdog)
end

-- =========
-- Startup
-- =========

--- Things that need to be done before entering the main loop for the first time.
---
--- Requires a position to start the walkback at.
---
--- Does not call the main loop after startup finishes.
--- @param pos MinecraftPosition
function mesh_os.startup(pos)
    -- Setup the walkback.
    walkback:setup(pos.position.x, pos.position.y, pos.position.z, pos.facing)
end

-- =========
-- Main loop
-- =========

--- This is the main loop of the operating system.
--- This will never return.
---
--- This loop needs to be hyper-optimized to minimize the time it takes to
--- continue running a task.
function mesh_os.main()
    -- Bring in locals to make yielding slightly faster.

    -- Queue event function
    ---@type function
    ---@diagnostic disable-next-line: undefined-field


    -- Yield function, directly yields to the lua engine
    local yield = _G.coroutine.yield

    -- Resume coroutines
    local status = _G.coroutine.status

    -- The empty string we pass to the yield, since we aren't actually yielding
    -- for any real reason, we need to push an event to the event queue, otherwise
    -- the OS would not resume until some other event happens.
    local yield_string = "yield"

    -- TODO: Move this into the task
    local result

    while true do
        -- TODO: Do we need these?
        -- Yield to the Lua engine, this means we yield twice per loop, but
        -- in-case the task request stuff breaks and there is nothing to
        -- queue(yield_string)

        -- Instead of blindly taking the next event, we always search for yield
        -- to prevent consuming other kinds of events.
        -- yield(yield_string)

        -- Create locals early as to not piss off goto
        local task
        local bool

        -- Are we sleeping?
        if wake_up_time ~= nil then
            print("Sleeping...")
            local now = epochFunction("utc")
            -- Are we done sleeping?
            ---@diagnostic disable-next-line: undefined-field
            if now >= wake_up_time then
                -- All done!
                print("Sleep finished!")
                wake_up_time = nil
                -- Cancel the timer if it is still going.
                if sleeping_timer_id ~= nil then
                    ---@diagnostic disable-next-line: undefined-field
                    os.cancelTimer(sleeping_timer_id)
                    sleeping_timer_id = nil
                end
            else
                local time_remaining_seconds = ((wake_up_time - now)/1000.0)
                print("Time remaining: " .. time_remaining_seconds .. " seconds.")
                -- We are still sleeping.
                -- Sleep for half of the remaining time.
                os_sleep(time_remaining_seconds / 2)
                goto skip_task
            end
        end

        -- Grab a task from the queue, unless it is empty.
        --- @type TurtleTask?
        task = task_queue[#task_queue]

        -- If there is no task, get new tasks.
        if not task then
            task = request_new_tasks()
            -- Double check
            panic.assert(task ~= nil, "Received no new tasks!")
        end

        -- Run the current task.

        -- Sometimes the resume calls actually are trying to pull for an event,
        -- thus if we get a string we need to pass in the event its asking for.
        if result ~= nil and type(result) == "string" then
            -- If its waiting for a yield event, we can just feed it back
            -- into it immediately, since the yield obviously finished.
            if result == yield_string then
                bool, result = resume(task.task_thread, yield_string)
            else
                -- TODO: Rewrite this to not pull in-line and use a safer function
                -- that will not block forever.
                print("Task is waiting for an event titled: \"", result, "\".")
                ---@diagnostic disable-next-line: undefined-field -- TODO:
                bool, result = resume(task.task_thread, os.pullEvent(result))
            end
        else
            ---@type boolean, TaskCompletion|TaskFailure|any
            bool, result = resume(task.task_thread)
        end

        -- Is the task over?
        if not bool then
            -- The task has ended. This either indicates that it actually
            -- finished, or that the the task threw an error.

            if result.kind == "success" then
                -- Nothing else to do! :D
                goto task_cleanup_done
            end

            -- TODO: actually recover lmao
            -- Task threw an error. Currently there is no recovery system for this.
            -- This should be a string.
            panic.panic("task died lol" .. helpers.serializeJSON(result))


            ::task_cleanup_done::
            -- Done running that task, so we remove it from the queue and loop!
            task_queue[#task_queue] = nil
        end

        -- This label is used when we are sleeping, as to not wake up the task
        -- while it is eeping ever so peacefully.
        ::skip_task::

        -- Handle events
        handle_events()

        -- Keep going!
    end
end

return mesh_os