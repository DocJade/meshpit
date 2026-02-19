-- Debugging stuff for testing.
-- Assumes networking is already loaded.

local constants = require("constants")

local debugging = {}

--- Step-locked syncing with the test harness.
function debugging.wait_step()
    NETWORKING.debugSend("wait")
    if NETWORKING.waitForPacket(constants.WAIT_STEP_TIMEOUT) then
        return
    end
    NETWORKING.debugSend("fail, no response from harness.")
    ---@diagnostic disable-next-line: undefined-field
    os.setComputerLabel("step failure")
end

return debugging
