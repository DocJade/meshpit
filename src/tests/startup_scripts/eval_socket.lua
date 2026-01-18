local url = "ws:/###URL###:###SOCKET###"
local ws, err = http.websocket(url)
if not ws then
    -- couldn't open the websocket.
    -- Nothing we can do.
    print("Error: " .. err)
    os.shutdown()
end
while true do
    local message = ws.receive()
    if message then
        local func, loadErr = load(message, "websocket_eval")
        if func then
            -- do a pcall so we dont crash on invalid code
            local success, runErr = pcall(func)
            if not success then
                print("Runtime Error: " .. runErr)
            end
        else
            print("Syntax Error: " .. loadErr)
        end
    else
        -- If message is nil, the socket closed
        print("Connection lost.")
        break
    end
end
ws.close()
os.shutdown()