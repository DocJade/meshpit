-- Weirdly, lua doesn't have some methods it really should.
local helpers = {}
local panic = require("panic")
print("Setting up helpers...")

--- Deep-copy a table (or anything), a lot of the time we do NOT want to take tables
--- by reference. So we need to copy it.
---@param input any
---@param seen nil
---@return table any a deep copy of the input
function helpers.deepCopy(input, seen)
    -- YIELD TEST TODO:
    os.queueEvent("yield")
    os.pullEvent("yield")
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
    local slice_start = slice_start or 1
    for i= slice_start, slice_end do
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

--- Cast a table into a string, no matter the internal data. Will NOT recurse into
--- sub tables. Meant for debugging only, as the ordering here is not stable.
---@param table table
---@return string
function forceStringTable(table)
    local final_string = "Data of table (" .. tostring(table) .. "): "
    for key, value in pairs(table) do
        final_string = final_string .. "[key: (" .. tostring(key) .. "), value: (" .. tostring(value) .. ")]"
    end
    return final_string
end

--Table types for linting to prevent returning the wrong things.

---@class SeenCleaned table
---@class Seen table

--- Clean up a type for JSON export. Will panic if the type or any sub-tables
--- contain mixed table types (ie a table that is both an array and kv pairs) and
--- will also panic if any of the keys used are not strings.
---
--- Since mixed table types panic, you make opt-in to completely discarding these
--- tables instead of panicking, but this WILL lose data.
---
--- The second returned value is a table of tables. Ignore it if you do not need it.
---
--- Is meant to be called recursively,
---@param value any
---@param seen Seen? an empty table please
---@param seen_cleaned SeenCleaned? an empty table please
---@param skip_invalid_tables boolean?
---@return any, SeenCleaned
function cleanForJSON(value, seen, seen_cleaned, skip_invalid_tables)
    local skip_invalid_tables = skip_invalid_tables or false
    -- TODO: some kind of yield in case this takes too long.
    os.queueEvent("yield")
    os.pullEvent("yield")

    ---@diagnostic disable-next-line: undefined-global
    local json_null = textutils.json_null

    ---@type Seen
    local seen = seen or {}
    -- We pass in and back out tables we've already seen to prevent needing to re-do work
    -- on tables that contain multiple duplicate table values under different keys.
    ---@type SeenCleaned
    local seen_cleaned = seen_cleaned or {}

    -- Skip values that don't need extra work.
    local t = type(value)

    -- We can directly pass back primitive types.
    if t == "number" or t == "string" or t == "boolean" then
        return value, seen_cleaned
    end

    -- If this is a nil, we need to use the special nil type.
    if t == "nil" or t == nil then
        return json_null, seen_cleaned
    end

    -- If it's a function, unfortunately we cannot get the name
    -- of it, but at least we can get the function ID... We can also tack on
    -- the definition line in case that helps.
    if t == "function" then
        return tostring(value) .. " defined on line " .. tostring(debug.getinfo(value, "S").linedefined), seen_cleaned
    end

    -- We don't care at all about threads or userdata, discard them entirely.
    -- Note on userdata: Its just a type that lets you store C/C++ values in
    -- ...somewhere? But AFAIK we do not use them.
    if t == "thread" or t == "userdata" then
        -- We can't blindly return nil here as that could cause gaps in the final
        -- array (if we're constructing an array). Since we shouldn't be seeing
        -- these anyways, we just use strings
        return t, seen_cleaned
    end

    -- Is this a json null?
    if value == json_null then
        -- It's just a null.
        return json_null, seen_cleaned
    end

    -- Must be a table. Have we already seen it?
    if seen[value] then
        -- Already seen this table.
        -- Did we already finish this?
        local maybe_cleaned = seen_cleaned[value]
        if maybe_cleaned then
            -- Already processed this table!
            return maybe_cleaned, seen_cleaned
        end

        -- If we end up here, that means we've hit a circular dependency. We need
        -- to break the cycle. Currently cant think of a clean way to resolve
        -- this situation so we just explode. Don't make self referencing tables!
        local printable_version = forceStringTable(value)
        panic.panic("Self referential table! " .. printable_version)
    end

    -- Mark it as seen. We will store the cleaned version once we're done.
    seen[value] = true

    -- Now we have to be careful to not try and store tables with mixed contents,
    -- as this would silently discard data in textutils.

    local array_item_count = 0
    -- cant count the hashmap alone, this will also count the array side.
    local combined_item_count = 0

    for _, _ in ipairs(value) do
        array_item_count = array_item_count + 1
    end

    for _, _ in pairs(value) do
        combined_item_count = combined_item_count + 1
    end

    -- Check if table is completely empty, we can skip if so!
    if (array_item_count == 0) and (combined_item_count == 0) then
        -- Empty table, return a null since it has `None` value.
        -- Thus the rust side can also interpret it as an array(?)
        seen_cleaned[value] = json_null
        return json_null, seen_cleaned
    end

    -- There is content, make sure that the table is not mixed.
    if (array_item_count < combined_item_count) and array_item_count ~= 0 then
        -- Table is mixed. Can't work with that.
        if CURRENTLY_PANICKING or false or skip_invalid_tables then
            print("Invalid table in cleanForJSON! (Mixed table) Opted to skip.")
            local xkcd_idk = "Invalid mixed table, skipped"
            seen_cleaned[value] = xkcd_idk
            return xkcd_idk, seen_cleaned
        end
        -- I want to at least see what was in the table still
        local printable_version = forceStringTable(value)
        panic.panic("Mixed table! Not allowed! table: " .. printable_version)
    end

    -- Table is not mixed. It must be an array if the array item count is greater
    -- than zero.
    local is_array = array_item_count ~= 0

    local cleaned_table = {}

    -- If this is an array, we also need to make sure there are no gaps
    -- > a = {}
    -- > a[1] = "test"
    -- > a[100] = "test"
    -- > print(#a)
    -- 1
    -- So we keep track of how many elements we see, and check at the end that
    -- the length matches
    local total_items = 0

    for k, v in pairs(value) do
        total_items = total_items + 1
        if is_array then
            -- Array handling
            -- Don't need to check the value of the key, since we know what type of
            -- table this is already.
            -- Recurse into the value
            -- Putting values in like this is safe in `pairs()` even though its
            -- not ipairs, since we are directly using the key number instead of
            -- assuming its sequential.
            local cleaned
            cleaned, seen_cleaned = cleanForJSON(v, seen, seen_cleaned, skip_invalid_tables)
            cleaned_table[k] = cleaned
        else
            -- Object/hashmap handling
            -- Make sure that the key is a string, since that's the only allowed
            -- type, unless we're panicking then we just need to get _SOMETHING_ out the door.
            local is_string = type(k) == "string"
            if (CURRENTLY_PANICKING or false) and not is_string then
                print("Invalid table in cleanForJSON! (Non string key) Opted to skip.")
                -- Just toss the whole table.
                local failure_message = "Invalid mixed table, skipped"
                return failure_message, seen_cleaned
            end
            panic.assert(is_string, "Non string key used in table! Not allowed!")

            local cleaned
            cleaned, seen_cleaned = cleanForJSON(v, seen, seen_cleaned, skip_invalid_tables)
            cleaned_table[k] = cleaned
        end
    end


    -- Post-array handling
    if is_array then
        -- Check for holes.
        panic.assert(array_item_count == total_items, "Array has holes! Not allowed!")
        -- Theoretically we can get back an empty array, so we will fix that as well
        if #cleaned_table == 0 then
            -- Return an empty array json thing instead
            seen_cleaned[value] = json_null
            return json_null, seen_cleaned
        end
    end


    seen_cleaned[value] = value
    return cleaned_table, seen_cleaned
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
    copy = cleanForJSON(input)

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
---
--- Returns a true, any pair when successful.
--- Returns a false, string with an error message from unserializeJSON on failure.
---@param json string
---@return boolean, any -- A success / fail, and the result of deserialization. You should hopefully know the type.
function helpers.deserializeJSON(json)
    -- careful! its deserialize instead of deserialize for some stupid reason
    ---@diagnostic disable-next-line: undefined-global
    local ok, result_or_error = pcall(textutils.unserializeJSON, json)
    if not ok then
        -- Well crap!
        return false, result_or_error
    end
    -- Worked!
    return true, result_or_error
end

print("Sanity checks...")
_ = helpers.serializeJSON("test")
_ = helpers.serializeJSON({})
_ = helpers.serializeJSON(nil)
_ = helpers.serializeJSON(1234)
local temp = {}
local temp_2 = {}
temp_2[1] = "inside"
local temp_3 = {}
temp_3["string key"] = "wow"
temp[1] = "test"
temp[2] = "second_test"
temp[3] = temp_2
temp[4] = temp_3
_ = helpers.serializeJSON(temp)
-- The following will panic due to self-reference detection.
-- Dont have a way to catch panics so, don't actually try it.
-- local circle = {}
-- circle["wow"] = circle
-- _ = helpers.serializeJSON(circle)
print("Done setting up helpers!")

return helpers