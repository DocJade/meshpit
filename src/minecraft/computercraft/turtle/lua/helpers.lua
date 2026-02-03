-- Weirdly, lua doesn't have some methods it really should.
local helpers = {}
print("Setting up helpers...")

--- Deep-copy a table (or anything), a lot of the time we do NOT want to take tables
--- by reference. So we need to copy it.
---@param input any
---@param seen nil
---@return table any a deep copy of the input
function helpers.deepCopy(input, seen)
    -- No need to deep copy if this is not a table.
    if type(input) ~= "table" then
        return input
    end
    seen = seen or {}
    -- skip if we've already seen this table
    if seen[input] then
        return seen[input]
    end
    local copy = {}
    seen[input] = copy
    -- recurse into the keys and values, since
    -- the keys can also be tables!
    for key, val in pairs(input) do
        copy[helpers.deepCopy(key, seen)] = helpers.deepCopy(val, seen)
    end
    -- Copy the metatable as well if it exists
    local meta = getmetatable(input)
    if meta then
        setmetatable(copy, helpers.deepCopy(meta, seen))
    end
    
    return copy
end

--- Turn any incoming type into a type we can turn into json.
--- Takes in values or keys, but do note that it does not take in both at the same time.
--- TODO: I'm worried this may cause computers to not yield for a while if the table is large. There needs to
--- be some yield in here.
---@param value any
---@param seen table an empty table please
---@return any any
local function packJSON(value, seen)
    local t = type(value)
    
    -- We can directly pass back primitive types.
    if t == "number" or t == "string" or t == "boolean" then
        return value
    end
    
    -- If this is a nil, we need to use the special nil type.
    if t == "nil" or t == nil then
        ---@diagnostic disable-next-line: undefined-global
        return textutils.json_null
    end
    
    -- If it's a function, unfortunately we cannot get the name
    -- of it, but at least we can get the function ID... We can also tack on
    -- the definition line in case that helps.
    if t == "function" then
        return tostring(value) .. "defined on line " .. tostring(debug.getinfo(value, "S").linedefined)
    end
    
    -- We don't care at all about threads or userdata, discard them entirely.
    -- Note on userdata: Its just a type that lets you store C/C++ values in
    -- ...somewhere? But AFAIK we do not use them.
    if t == "thread" or t == "userdata" then
        -- This is different from a json null, the serializer will completely ignore this value.
        return nil
    end

    -- Keep track of tables we've seen, avoids infinite recursion.
    
    -- The only remaining type is a table. Thus we will recurse into the table to clean it up.
    -- Unless we have already seen this table, in which case, we just mark it as a duplicate.
    if seen[value] then
        return "Already packed this table."
    end

    -- Mark the current value as seen, then start turning it into an object of key value pairs.
    seen[value] = true

    local struct = {
        pairs = {}
    }

    for key, value in pairs(value) do
        -- Recuse into keys and values to pack them.
        local packed_key = packJSON(key, seen)
        local packed_value = packJSON(value, seen)

        -- Now if either the key or the value is nil, we have no need to store it.
        if packed_key == nil or packed_value == nil then
            goto continue
        end

        -- Otherwise, this pair is now in a serializable format.
        table.insert(struct.pairs, {
            key = packed_key,
            value = packed_value
        })

        ::continue::
    end
    
    -- Return the cleaned table
    return struct
end

--- Unpack our custom json table format back into a normal lua table.
---@param packed string
---@return any unpacked
function unpackJSON(packed)
    -- Only need special logic for tables
    if type(packed) ~= "table" then
        return packed
    end

    -- Check if this is actually a packed table
    if not packed.pairs or type(packed.pairs) ~= "table" then
        -- Not our packed format. Cannot unpack.
        -- Should already be in the correct format then.
        return packed
    end

    local new_table = {}

    -- Unpack our table!
    -- We do not care about the keys from the originating table, as
    -- the keys we want are packed into the pair.
    for _, pair in ipairs(packed) do
        -- If anything is nil (which it should never be) we skip the pair.
        if pair.key == nil or pair.value == nil then
            goto continue
        end

        -- Unpack the inner keys and values, then put them into our new table.
        local unpacked_key = unpackJSON(pair.key)
        local unpacked_value = unpackJSON(pair.value)
        new_table[unpacked_key] = unpacked_value

        ::continue::
    end

    -- All done!
    return new_table
end


--- The built-in json serializer is not good enough.
--- 
--- The textutils.serialiseJSON() method does not work with:
--- - Mixed tables
--- - Non-integer keys into tables
--- - Recursion within tables
--- 
--- Thus we have our own that pre-cleans the data.
---@param input any
---@return string json the outgoing json string.
function helpers.serializeJSON(input)
    -- Make a deep copy of the input as to not alter the incoming table, and
    -- clean it up for export.
    local copy = helpers.deepCopy(input)
    copy = packJSON(copy, {})

    -- Serialize that with the standard serializer, now that it's in a
    -- format that it likes.
    ---@diagnostic disable-next-line: undefined-global
    local ok, result = pcall(textutils.serializeJSON, copy)
    if not ok then
        -- Well crap!
        panic.panic(tostring(result))
    end

    return result
end

--- Deserialize our custom json format back into tables.
--- 
--- This assumes the incoming type is proper json! If it is not, the deserialization will throw an error.
--- It is the Rust-side's job to ensure we never send malformed json.
---@param json string
---@return any anything the result of deserialization. You should hopefully know the type.
function helpers.deserializeJSON(json)
    -- careful! its unserialize instead of deserialize for some stupid reason
    ---@diagnostic disable-next-line: undefined-global
    local ok, result = pcall(textutils.unserializeJSON, json)
    if not ok then
        -- Well crap!
        panic.panic(tostring(result))
    end
    -- unpack the data as needed
    -- we can pass by value here.
    return unpackJSON(result)
end

print("Sanity checks...")
local _ = helpers.serializeJSON("test")
local _ = helpers.serializeJSON({})
local _ = helpers.serializeJSON(nil)
local _ = helpers.serializeJSON(1234)
local circle = {}
circle["wow"] = circle
local _ = helpers.serializeJSON(circle)
print("Done setting up helpers!")

return helpers