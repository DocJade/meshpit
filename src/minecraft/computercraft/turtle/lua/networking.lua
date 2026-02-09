---@diagnostic disable: undefined-global, undefined-field
-- Everything related to networking. Currently very basic.
print("Setting up networking...")
local panic = require("panic")
local helpers = require("helpers")

-- Should be a good enough seed.
math.randomseed(os.getComputerID() * os.epoch("utc"))

-- All of our local state.
NETWORKING = {}

-- All compuers communicate over the same websocket, only differentiated by their computer ID
-- via sending it in the initial handshake.
-- TODO: This is currently pinned to localhost. Should we do this another way?
NETWORKING.SERVER_URL = "ws://localhost:4816/meshpit"
NETWORKING.websocket = nil
NETWORKING.HEADERS = {
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
    if NETWORKING.websocket then
        return
    end

    -- Try connecting, also here we send the headers for the computer's ID.
    -- We wait for at most 10 seconds.
    local socket, error_string = http.websocket(NETWORKING.SERVER_URL, NETWORKING.HEADERS, 10)

    -- If that didn't work, give up.
    if not socket then
        panic.force_reboot("Failed to connect to websocket! " .. tostring(error_string))
    end

    -- Got a websocket!
    NETWORKING.websocket = socket
end

-- Do the initial connection.
-- This will block, but thats fine, we we really shouldn't be doing anything
-- without a connection.
print("Calling connect...")
-- This network connection is global.
connect()
print("Done!")

--- The different kinds of outgoing and incoming packets
---@alias PacketType
---| "panic" Used when panics are thrown. Format is very wild as its almost the entire lua state.
---| "walkback" A popped walkback.
---| "unknown" Format is not specified.
---| "debugging" Self explanatory

--- The packet format used to communicate outwards and inwards from the turtle.
---@class packet
---@field id number The computer's ID
---@field uuid string A unique identifier for this packet
---@field timestamp number Seconds since unix epoch
---@field packet_type PacketType The kind of packet this is.
---@field data any The inner data contained within this table.


--- Constructs a packet in a the set format.
--- 
--- Requires a UUID.
---@param data string|table
---@param type PacketType The type of this packet. If not set, will set to unknown.
---@param UUID string
---@return string json a json string
local function formatPacket(data, type, UUID)
    ---@type packet
    local packet = {
        id = os.getComputerID(),
        uuid = UUID,
        timestamp = os.epoch("utc"),
        packet_type = type or "unknown",
        data = data
    }

    -- Now turn that into a json string.
    -- There may be duplicate tables. If there are, then we will allow them.
    -- Wrap this in a pcall, and panic if it fails.
    local ok, result = pcall(helpers.serializeJSON, packet)
    if not ok then
        panic.panic("Failed to clean a table for json! " .. tostring(result), true)
    end

    return result -- has to go here or linter gets mad lol.
end

--- Send a message out the websocket. Does not wait for a reply.
--- 
--- Takes in a table or a string. Will put the input into a packet before sending.
--- Deeply copies tables instead of passing them by reference.
--- Requires a UUID and packet type.
--- 
--- Returns `false` if sending fails for any reason.
---@param message table|string
---@param type PacketType The type of this packet. If not set, will set to unknown.
---@param UUID string
---@returns boolean
local function send(message, type, UUID)
    if not NETWORKING.websocket then
        -- No websocket to send on!
        -- We cannot run healthy here. We assume
        -- callers have already ran healthy. The is nothing we can do.
        panic.force_reboot("Tried to send a message without a websocket!")
        return false -- this never gets returned
    end
    -- diagnostic disables since i am casting in place.
    local message_copy = helpers.deepCopy(message)
    ---@diagnostic disable-next-line: cast-local-type
    message_copy = formatPacket(message_copy, type, UUID)
    local ok, result = pcall(NETWORKING.websocket.send, message_copy)
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
    if not NETWORKING.websocket then
        -- No websocket to listen on!
        panic.force_reboot("Cannot listen without a websocket!")
        return false, "impossible" -- this never gets returned
    end
    -- Wait for a message
    local ok, message_or_pcall_error, binary_or_fail = pcall(NETWORKING.websocket.receive, timeout)

    if not ok then
        -- Pcall itself failed.
        return false, message_or_pcall_error
    end

    if type(binary_or_fail) ~= "boolean" then
        -- Got a failure message.
        return false, binary_or_fail
    end

    -- Some other weird error, should have already been caught by the
    -- error string check
    if message_or_pcall_error == nil then
        local panic_message = "Failed to receive message for an unknown reason! | ok: "
        panic_message = panic_message .. tostring(ok) .. " | message_or_pcall_error: "
        panic_message = panic_message .. tostring(message_or_pcall_error) .. " | binary_or_fail: "
        panic_message = panic_message .. tostring(binary_or_fail)
        panic.panic(panic_message) -- Might still be able to send this out somehow.
    end
    
    -- unpack the returned packet
    local ok, result_or_failure = helpers.deserializeJSON(message_or_pcall_error)
    if not ok then
        -- Unpacking failed for some reason!
        panic.force_reboot("Failed to unpack received packet! : " .. tostring(result_or_failure))
    end

    return true, result_or_failure
end

-- TODO: Check if the socket is healthy, automatically re-connects if needed.



--- One way message to the control server, does not expect a response. Should
--- only be used for debugging.
--- 
--- The incoming type will be converted to a json string, unless the incoming type
--- is already a string, in which case we assume it is already in the format that you
--- wish to send.
---@param message table|string
function NETWORKING.debugSend(message)
    -- Check that the socket is ready first.
    -- healthy() --TODO: Do this in a better way.

    -- Create a UUID for this message
    local UUID = getUUID()

    -- send it!
    -- We try at most 5 times before completely giving up.
    for i = 1, 5 do
        if send(message, "debugging", UUID) then
            return
        end
    end

    -- Failed to send all 5 times. This should not happen.
    panic.force_reboot("Failed to send a message after 5 attempts!")
end

--- Block and wait for any incoming message.
--- 
--- Takes in a timeout. Returns a boolean on wether we got anything before the timeout ended.
---@param timeout number
---@return boolean, any
function NETWORKING.waitForPacket(timeout)
    -- very hollow wrapper at the moment lol.
    local bool, result = receive(timeout)
    return bool, result
end

print("Done setting up networking!")