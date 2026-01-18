---@diagnostic disable: undefined-field
local url = "ws:/###URL###:###SOCKET###"
ws, err = http.websocket(url) 

if not ws then
    print("Error: " .. err)
    os.shutdown()
end

while true do
    local message = ws.receive()
    if message then
        local func, loadErr = load(message, "websocket_eval")
        if func then
            local success, runErr = pcall(func)
            if not success then
                print("Runtime Error: " .. runErr)
                -- also send error out the websocket so rust can see it
                ws.send("ERROR: " .. runErr) 
            end
        else
            print("Syntax Error: " .. loadErr)
        end
    else
        print("Connection lost.")
        break
    end
end
ws.close()
os.shutdown()