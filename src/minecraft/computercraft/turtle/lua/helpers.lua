-- Weirdly, lua doesn't have some methods it really should.
local helpers = {}

--- Deep-copy a table, a lot of the time we do NOT want to take tables
--- by reference. So we need to copy it.
---@param table table
---@return table table a copy of the table
function helpers.deepCopy(table)
    local copy = {}
    for key, val in pairs(table) do
        if type(val) == "table" then
            -- recurse
            copy[key] = helpers.deepCopy(val)
        else
            copy[key] = val
        end
    end
    return copy
end


--- The built-in json serializer is not good enough.
--- 
--- The textutils.serialiseJSON() method does not work with:
--- - Mixed tables
--- - Non-integer keys into tables
--- - Recursion within tables
--- 
--- Thus we have our own.
---@param table table
---@return string json the outgoing json string.
function helpers.serializeJSON(table)
    
end

--- Deserialize our custom json format back into tables.
---@param table table
---@return string json the outgoing json string.
function helpers.deserializeJSON(table)
    
end

return helpers