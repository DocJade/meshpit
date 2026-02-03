---@diagnostic disable: undefined-global, undefined-field
-- Everything related to networking. Currently very basic.
print("Setting up networking...")
local panic = require("panic")
local helpers = require("helpers")

-- Should be a good enough seed.
math.randomseed(os.getComputerID() * os.epoch("utc"))

-- All of our local state.
local networking = {}

-- All compuers communicate over the same websocket, only differentiated by their computer ID
-- via sending it in the initial handshake.
-- TODO: This is currently pinned to localhost. Should we do this another way?
local SERVER_URL = "localhost:4816/meshpit"
local websocket = nil
local HEADERS = {
    ["Computer-ID"] = tostring(os.getComputerID())
}

--- To prevent issues when multiple messages are sent in the same second, each packet
--- gets a UUID to differentiate it. Do note that re-transmitting a packet on failure
--- should continue to use the same UUID, just in case the control computer got it.
--- 
--- For simplicity, these are not real 128 bit compliant UUIDs. This may change in the
--- future if I feel like writing that for some reason.
---@return string UUID a UUID.
local function getUUID()
    -- Eight characters should be plenty.
    -- We only use uppercase ascii, so a collision within a tick from one computer
    -- would require a 1/~14 million chance. Good enough.
    local UUID = ""
    for i = 1, 8 do
        UUID = UUID .. string.char(math.random(65, 90))
    end
    return UUID
end

--- Connect to the websocket. If this fails, we give up completely, since
--- we cannot report the error at all.
--- 
--- This should be called once on startup.
local function connect()
    -- skip if the websocket is already open, skip.
    if websocket then
        return
    end

    -- Try connecting, also here we send the headers for the computer's ID.
    -- We wait for at most 10 seconds.
    local socket, error_string = http.websocket(SERVER_URL, HEADERS, 10)

    -- If that didn't work, give up.
    if not socket then
        panic.force_reboot("Failed to connect to websocket! " .. tostring(error_string))
    end

    -- Got a websocket!
    websocket = socket
end

-- Do the initial connection.
-- This will block, but thats fine, we we really shouldn't be doing anything
-- without a connection.
print("Calling connect...")
connect()
print("Done!")


--- Constructs a packet in a the set format.
--- 
--- Requires a UUID.
---@param message string|table
---@param UUID string
---@return string json a json string
local function formatPacket(message, UUID)
    local packet = {
        --TODO: redundant?
        id = os.getComputerID(),

        uuid = UUID,

        timestamp = os.epoch("utc"),

        data = message
    }

    -- Now turn that into a json string.
    -- There may be duplicate tables. If there are, then we will allow them.
    -- Wrap this in a pcall, and panic if it fails.
    local ok, result = pcall(helpers.serializeJSON, packet)
    if not ok then
        -- Failure. Give up!
        -- Chances are that this will make panic fail too, so we disable
        -- the variable output.
        panic.panic("Failed to clean a table for json! " .. tostring(result), true)
    end

    return result
end

--- Send a message out the websocket. Does not wait for a reply.
--- 
--- Takes in a table or a string. Will put the input into a packet before sending.
--- Deeply copies tables instead of passing them by reference.
--- Requires a UUID.
--- 
--- Returns `false` if sending fails for any reason.
---@param message table|string
---@param UUID string
---@returns boolean
local function send(message, UUID)
    if not websocket then
        -- No websocket to send on!
        -- We cannot run healthy here. We assume
        -- callers have already ran healthy. The is nothing we can do.
        panic.force_reboot("Tried to send a message without a websocket!")
        return false -- this never gets returned
    end
    -- diagnostic disables since i am casting in place.
    local message_copy = helpers.deepCopy(message)
    ---@diagnostic disable-next-line: cast-local-type
    message_copy = helpers.serializeJSON(message_copy)
    ---@diagnostic disable-next-line: cast-local-type
    message_copy = formatPacket(message_copy, UUID)
    local ok, result = pcall(websocket.send, message_copy)
    return ok
end

--- Waits for any message to come into the websocket. Calling this with zero timeout will not block.
---@param timeout number|nil
---@returns boolean, any
local function receive(timeout)
    local timeout = timeout
    if timeout == nil then
        print("Please specify timeouts!")
        timeout = 0
    end
    if not websocket then
        -- No websocket to listen on!
        panic.force_reboot("Cannot listen without a websocket!")
        return false, "impossible" -- this never gets returned
    end
    -- Wait for a message
    local ok, result = pcall(websocket.receive, timeout)
    if not ok then
        -- Did it just time out?
        if result == "Timed out" then
            return false, result
        end
        -- Something actually failed.
        -- TODO: handling errors here
        panic.force_reboot("Failed receive packet for reason other than timeout! : " .. tostring(result))
    end
    
    -- unpack the returned packet
    local ok, second_result = pcall(helpers.deserializeJSON, result)
    if not ok then
        -- Unpacking failed for some reason!
        panic.force_reboot("Failed to unpack received packet! : " .. tostring(second_result))
    end

    return true, second_result
end

--- Check if the socket is healthy, automatically re-connects if needed.
local function healthy()
    -- Ping pong time
    -- TODO: Replace this with something that makes more since, yes this
    -- will make 2 packets for every packet, but its fine for now.
    local worked = true -- if we skip the test, this needs to be true
    if websocket then -- Skip if there is already no websocket
        websocket.
        worked = send("health", getUUID())
    end
    if not worked then
        -- Sending didn't work. Either that timed out, or the websocket is dead.
        -- Remove the socket.
        websocket = nil
    end
    
    -- Re-negotiate the websocket if needed.
    if not websocket then
        connect()
    end
end


--- One way message to the control server, does not expect a response.
--- 
--- The incoming type will be converted to a json string, unless the incoming type
--- is already a string, in which case we assume it is already in the format that you
--- wish to send.
---@param message table|string
function networking.sendToControl(message)
    -- Check that the socket is ready first.
    healthy()

    -- Create a UUID for this message
    local UUID = getUUID()

    -- send it!
    -- We try at most 5 times before completely giving up.
    for i = 1, 5 do
        if send(message, UUID) then
            return
        end
    end

    -- Failed to send all 5 times. This should not happen.
    panic.force_reboot("Failed to send a message after 5 attempts!")
end

--- Wait for any incoming message. This is a temporary method for testing, i think? TODO:
--- 
--- Takes in a timeout. Returns a boolean on wether we got anything before the timeout ended.
---@param timeout number
---@return boolean, any
function networking.waitForPacket(timeout)
    -- very hollow wrapper at the moment lol.
    local bool, result = receive(timeout)
    return bool, result
end

-- And finally return the functions for use.
print("Done setting up networking!")
return networking