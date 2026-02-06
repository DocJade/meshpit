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

--- Create a string from a table, used for indexing into hashmaps and such.
--- 
--- The input table must obey the following rules:
--- - The keys and values must be types that can be cast to strings safely
--- - - string, number, boolean (you should really not use these in keys)
--- - There must not be any duplicate keys in the table
--- - - This also applies to having a key at `1` and `"1"`, as these would both
--- - - map to the same string key.
--- 
--- Tables that do not obey these rules will return nil.
--- 
--- Does not modify the incoming table.
--- 
--- No method to cast back from this format is provided. This is by design,
--- its supposed to act as our hash function for generic tables.
---@generic K : string|number|boolean
---@generic V : string|number|boolean
---@param input_table table<K, V>
---@return string|nil
function helpers.keyFromTable(input_table)
    local keys = {}
    local seen_keys = {}

    -- Ignore the linter, its hallucinating here about k,v

    -- Pre-sort the keys since we need them to be in order, and table.sort() sorts
    -- the values, and provides no way to sort keys.
    for k, _ in pairs(input_table) do
        -- Also check that the keys are valid
        local k_t = type(k)
        local k_ok = k_t == "string" or k_t == "number" or k_t == "boolean"
        if not k_ok then
            return nil
        end
        local new_key = tostring(k)
        -- Duplicate key?
        if seen_keys[new_key] ~= nil then
            return nil
        end
        seen_keys[new_key] = true
        table.insert(keys, new_key)
    end

    -- Sort the keys
    table.sort(keys)
    
    -- Now add the values.
    local ordered_pairs = {}
    for i = 1, #keys do
        local key = keys[i]
        local value = input_table[key]

        -- Make sure value is valid as well
        local v_t = type(value)
        local v_ok = v_t == "string" or v_t == "number" or v_t == "boolean"
        if not v_ok then
            return nil
        end
        local new_value = tostring(value)
        -- "k:v"
        ordered_pairs[i] = keys[i] .. ":" .. new_value
    end

    -- Concat those into a string that we can use.
    -- "k:v|k:v|k:v"
    return table.concat(ordered_pairs, "|")
end

--- Check if two values are exactly the same by value. Also checks if they are
--- the same type. This will be very slow on large tables or tables that use
--- other tables as keys.
--- 
--- Panics on threads, functions, or userdata.
--- 
--- This aims to cover most edge cases, but theoretically if create a table with
--- several deeply equal table keys that live at different addresses, this
--- could falsely return true even if the tables are not COMPLETELY identical.
--- This is close enough. You really shouldn't use tables as keys anyways.
--- 
--- Does not check metatables.
---@generic T
---@param a T
---@param b T
---@param seen table|nil? Internal for recursion, not required.
---@return boolean
function helpers.deepEquals(a, b, seen)
    -- types are the same
    local t_a = type(a)
    if t_a ~= type(b) then
        return false
    end

    -- This function is not meant to be used for threads, functions or userdata.
    if t_a == "thread" or t_a == "function" or t_a == "userdata" then
        local message = "Attempted to run deepEquals on an unsupported type ["
        message = message .. t_a .. "]!"
        panic.panic(message)
        return false -- never called.
    end

    -- Make sure that a or b are non NaN
    if a ~= a or b ~= b then
        -- There's a nan!
        -- Nan's are never equal to themselves,
        -- but we can still return that they are both nan in this case.
        local a_nan = a ~= a
        local b_nan = b ~= b
        -- We return DEEP type/value equality here, not mathematical equality.
        return a_nan and b_nan
    end

    -- Then, if its not a table, we can compare by value
    if t_a ~= "table" then
        return a == b
    end

    -- Must be a table, we can check if they reference the same data.
    if a == b then
        return true
    end

    -- Need to compare at the value level. So time to recurse.
    -- Need to keep track of seen items as to not infinitely recurse.
    seen = seen or {}
    if seen[a] == b then
        return true
    end
    seen[a] = b

    -- Track how many items `a` has.
    local count_a = 0

    -- Since order is unspecified, we cant iterate the keys in parallel,
    -- we must index the `b` table with the `a` table key.
    --
    -- This also checks if the keys used to index into the tables are the same,
    -- which makes this slow for hashmaps, but this is a deep check after all.
    for ka, va in pairs(a) do
        local vb = b[ka]
        
        -- if vb is nil, it could be due to indexing with tables, thus having
        -- different key references while the insides of the keys are actually
        -- still the same. We must recurse into the keys if so.
        if vb ~= nil then
            -- Some value, either a non-table index, or a matching reference index.
            if not helpers.deepEquals(va, vb, seen) then
                return false
            end
        elseif type(ka) == "table" then
            -- Table did not match on reference, but could still have the
            -- same content deep-down.

            -- Need to check if `b` has a key that matches deeply.
            local found_match = false
            for kb, new_vb in pairs(b) do
                -- Only need to check table keys
                if type(kb) ~= "table" then
                    goto skip
                end

                -- New table key, check
                if not helpers.deepEquals(ka, kb, seen) then
                    -- wrong table
                    goto skip
                end

                -- Tables match, do keys match?
                if not helpers.deepEquals(va, new_vb, seen) then
                    -- Values did not match! Equal keys, but not equal values
                    -- However, its possible (although very gross) that there
                    -- could be multiple keys with the same underlying values
                    -- in b, thus we have to exhaust all of the possibilities
                    goto skip
                end

                -- Everything checks ou!
                found_match = true
                ::skip::
            end

            -- Find anything?
            if not found_match then
                return false
            end
        end
        count_a = count_a + 1
    end

    -- Finally, check that `b` did not have more items than `a`
    local count_b = 0
    for _ in pairs(b) do
        count_b = count_b + 1
    end

    return count_a == count_b
end

--- Get a sub-slice of a array. This slice is inclusive on both ends.
--- 
--- Do note that this will NOT work on tables that have keyed values.
--- 
--- If the slice contains tables, they are by reference, and NOT copied, so
--- be aware of that.
---@generic T
---@param input_table T[]
---@param slice_start number? Defaults to 1
---@param slice_end number? Defaults to the end of the table
---@return T[]
function helpers.slice_array(input_table, slice_start, slice_end)
    local slice = {}
    for i in slice_start or 1, slice_end or #input_table do
        slice[#slice+1] = input_table[i]
    end
    return slice
end

--- Unwrap a T|nil value, asserting that is is not nil.
---@generic T
---@param value T|nil
---@return T
function helpers.unwrap(value)
    assert(value ~= nil, "Unwrapped on a nil!")
    -- Tell linter this must no longer be nil.
    ---@cast value -nil
    return value
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
_ = helpers.serializeJSON("test")
_ = helpers.serializeJSON({})
_ = helpers.serializeJSON(nil)
_ = helpers.serializeJSON(1234)
local circle = {}
circle["wow"] = circle
_ = helpers.serializeJSON(circle)
print("Done setting up helpers!")

return helpers