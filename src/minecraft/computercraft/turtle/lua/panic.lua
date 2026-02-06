-- Used when things get out of hand!

-- Table that is used to call the panic handler.
-- Empty, as it is just for calling the method.
panic = {}

--- The panic method. Takes in a panic message.
--- 
--- Tthe computer is assumed to be in an un-recoverable state,
--- and thus will completely rebooting as soon as it is able
--- to relay all of its panic data.
--- 
--- This will automatically grab table data as well, but there are cases where you
--- don't need, don't want, or can't have that, so you may disable this behavior,
--- and only return the message with a stack trace.
--- 
--- Takes in a panic message.
--- @param message string
--- @param message_only boolean?
--- @return nil
function panic.panic(message, message_only)
    print("Panic! : " .. message)
    -- Requires networking to be able to communicate.
    local networking = require("networking")
    -- Traceback automatically adds the message to the top.
    local trace = debug.traceback(message)
    -- Only grab the variables if needed.
    local local_vars, the_up_values = {"variables disabled"}, {"variables disabled"}
    if not message_only then
        local_vars = panicLocals()
        the_up_values = panicUpValues()
    end

    ---@alias PanicData {stack_trace: string, locals: table, up_values: table} 
    ---@type PanicData
    panic_data = {
        -- A stack trace of where the panic was called.
        stack_trace = trace,

        -- Every local variable.
        -- In the format of an array of pairs.
        locals = local_vars,

        -- Every external variable we are referencing. This table has no overlap with locals.
        -- In the format of an array of pairs.
        up_values = the_up_values,
    }

    -- Transmit that table to control.
    -- This will automatically turn the table into json.
    networking.sendToControl(panic_data)

    -- Reboot.
    ---@diagnostic disable-next-line: undefined-field
    os.reboot();
end

--- Assert a condition to be true, otherwise panic.
---@param condition boolean
---@param message string
---@param message_only boolean?
---@return nil
function panic.assert(condition, message, message_only)
    if condition or false then -- cover nil more explicitly
        panic.panic(message, message_only or false)
    end
end

-- Functions for getting local and global variables
-- https://stackoverflow.com/questions/2834579/print-all-local-variables-accessible-to-the-current-scope-in-lua
function panicLocals()
    local variables = {}
    local idx = 1
    while true do
        local ln, lv = debug.getlocal(2, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

function panicUpValues()
    local variables = {}
    local idx = 1
    local func = debug.getinfo(2, "f").func
    while true do
            local ln, lv = debug.getupvalue(func, idx)
            if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

-- Additionally, it is possible that a failure prevents us from sending anything out the
-- network. Thus we have a restart panic. TODO: This panic could in theory place a text file
-- somewhere in the future to report this kind of error again later, but I'm not gonna do that
-- right now.

--- Reboot the computer due to a failure.
--- 
--- Use this when you know the networking is completely unreachable and you cannot recover.
--- @param message string
function panic.force_reboot(message)
    print("Forced reboot panic! : " .. message)
    -- Not much we can do here, but to prevent fast boot-looping, we will stall for 30 seconds.
    -- We will also shout out the message on as many outputs as we can.
    ---@diagnostic disable-next-line: undefined-global
    printError(message)
    ---@diagnostic disable-next-line: undefined-field
    os.setComputerLabel(message)

    ---@diagnostic disable-next-line: undefined-field
    os.sleep(30)
    ---@diagnostic disable-next-line: undefined-field
    os.reboot()
end

return panic