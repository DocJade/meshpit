-- Smelts items, duh!

local task_helpers = require("task_helpers")
local helpers = require("helpers")

--- The name of the furnace. We do not use the fancy furnaces, because change
--- scares me.
local FURNACE_PATTERN = "minecraft:furnace"

-- Yes globals are gross. I dont care
local FURNACE_PERIPHERAL = nil


--- Assumptions this task makes:
--- - The turtle already has a furnace in its inventory.
--- - There is space below the turtle for the furnace to be placed. If not, the
---   there needs to be an open space above the turtle so it may move up to place
---   the furnace.
--- - The turtle has a tool that can break furnaces.
---
--- Task completion states:
--- - All of the requested items have been smelted.
---
--- Task failures states:
--- - The turtle cannot place its furnace due to not having one, or having no room
---   to place it.
--- - There is not enough fuel to finish smelting
---
--- Notes:
--- - Mining a furnace does not drop the items on the floor if there is space in
---   the turtle's inventory
--- - Due to the fact that furnaces are treated as generic inventories, we cannot
---   directly access them. MOREOVER the side that you turtle.drop() into actually
---   matters, so being on top of it we can only place and pull items from the top
---   slot (ingredient) of the furnace. Thus we have to use push to move items
---   around inside of the furnace. Moreover, we cannot take from the result slot
---   from the top, so we'll just have to mine the whole turtle. We can monitor
---   the slots via the wrapped peripheral to check if there are items in the
---   slots.
--- - The shortest burning fuel is bamboo at 2.5 seconds. We could build a lookup
---   table for all of the fuel values, but instead, we can put fuel into the
---   furnace and measure how long it takes for the second item of that fuel to
---   be consumed.
---   - But thats too complicated. So not right now.
--- - Items cannot be pushed into the output slot of the turtle, however any item
---   can go into the ingredient slot.


--- The configuration for the smelting task
---
--- We assume there is space in our inventory for all of the resulting items.
---
--- Takes in a list of item names to be smelted (IE: put into the furnace, not
--- the resulting item) and a list of allowed fuels to use for the smelting process.
---
--- If you want to smelt more than one stack of the same item, you cannot set the
--- limit higher than 64. Thus you can only smelt at most one stack at a time if you
--- want to control how much you're smelting. Do note that you can just add the
--- same item to the queue multiple times if needed.
---
--- Both of these lists are ordered by priority.
---
--- Smelting will use fuels in order until all items have been smelted, or no
--- fuel remains. Be careful not to use up all of your fuel by smelting too much
--- at once!
---
--- Do note that we only take one item to smelt at
--- @class SmeltingData
--- @field name "smelt_task"
--- @field to_smelt SmeltItem[] -- See SmeltItem
--- @field fuels string[] -- String patterns, matches names.

--- An item to smelt. Comes with an optional limit, otherwise all matching
--- items in the inventory will be smelted before moving on.
--- @class SmeltItem
--- @field name_pattern string
--- @field limit number?


--
--
--
--
--
--
-- local worked, amount_moved = pcall(FURNACE_PERIPHERAL.pushItems, peripheral.getName(FURNACE_PERIPHERAL), source, nil, destination)
--
--
--
--
--
--

--- See how many items are in a slot of the furnace. Returns `nil` if slot is
--- empty.
--- 1: Ingredient
--- 2: Fuel
--- 3: Result
--- @param slot number
--- @return number|nil
function furnace_slot_count(slot)
    ---@diagnostic disable-next-line: need-check-nil, undefined-field
    local list = FURNACE_PERIPHERAL.list()
    return (list[slot] or {count = nil}).count
end

--- Insert an item into the ingredient slot from the currently selected slot.
---
--- Returns false if the ingredient slot already has items in it.
--- @param wb WalkbackSelf
--- @return boolean
function insert_ingredient(wb)
    -- Is the ingredient slot open?
    if furnace_slot_count(1) ~= nil then
        return false
    end

    -- Drop em in
    -- No need to check the result of this, since we know the slot is empty.
    wb:dropDown()
    return true
end

--- Pulls the resulting items from smelting into the currently selected slot.
---
--- Returns false if the furnace still has ingredients. You can only pull from
--- a furnace that has finished smelting.
---
--- Shuffles items around if needed.
---
--- @param wb WalkbackSelf
--- @return boolean
function pull_result(wb)
    -- Nothing to do if slot is empty
    if furnace_slot_count(3) == nil then
        return false
    end

    -- Is there stuff in the ingredient slot?
    if furnace_slot_count(1) ~= nil then
        -- Cant.
        return false
    end

    -- Pull the item.
    ---@diagnostic disable-next-line: need-check-nil, undefined-field, undefined-global
    local worked, _ = pcall(FURNACE_PERIPHERAL.pushItems, peripheral.getName(FURNACE_PERIPHERAL), 3, nil, 1)
    task_helpers.assert(worked)
    wb:suckDown()
    return true
end

--- Inserts fuel into the furnace from the currently selected slot.
--- Shuffles items around if needed.
--- @param wb WalkbackSelf
function insert_fuel_item(wb)
    local original_slot = wb:getSelectedSlot()
    local ingredient_swap_slot = nil

    -- Empty out the ingredient slot if needed.
    if furnace_slot_count(1) ~= nil then
        -- We need to store this first. Find a free slot and move it in.
        ingredient_swap_slot = wb:FindEmptySlot()
        if ingredient_swap_slot == nil then
            -- No room in our inventory. Can't do anything.
            task_helpers.throw("inventory full")
        end
        ---@cast ingredient_swap_slot number

        -- Pull the item into there
        wb:select(ingredient_swap_slot)
        wb:suckDown()
        wb:select(original_slot)
    end

    -- Put in the fuel item
    wb:dropDown()

    -- Move it into the correct slot
    ---@diagnostic disable-next-line: need-check-nil, undefined-field, undefined-global
    local worked, _ = pcall(FURNACE_PERIPHERAL.pushItems, peripheral.getName(FURNACE_PERIPHERAL), 1, nil, 2)
    task_helpers.assert(worked)

    -- Put back the ingredient if needed
    if ingredient_swap_slot ~= nil then
        wb:select(ingredient_swap_slot)
        wb:dropDown()
        wb:select(original_slot)
    end

    -- All done.
end

--- Add the next item in the queue of items to smelt into the furnace.
---
--- Returns false if we are out of items to smelt, or if there are already items
--- in the ingredient slot.
--- @param task TurtleTask
--- @param indexes SmeltingIndexes
--- @return boolean
function add_next_item(task, indexes)
    local wb = task.walkback
    local task_data = task.definition.task_data
    local current_index = indexes.current_item_index
    --- @cast task_data SmeltingData

    -- Do we have stuff to do?
    if #task_data.to_smelt == current_index - 1 then
        -- Out of stuff to do
        return false
    end

    -- Can we insert items?
    if furnace_slot_count(1) ~= nil then
        -- no
        return false
    end

    -- Make sure we have enough.
    local current_item = task_data.to_smelt[current_index]
    local amount_needed = current_item.limit
    if amount_needed ~= nil then
        local total = wb:inventoryCountPattern(current_item.name_pattern)
        if total < current_item.limit then
            -- Not enough items. Bad configuration resulted in this, however this
            -- is just an assumption at this point.
            -- Cleanup and die.
            wb:digDown()
            task_helpers.throw("assumptions not met")
        end
    end

    -- Start putting it in

    ::need_more:: -- yes i know, shut up

    -- Find the item
    local slot = wb:inventoryFindPattern(current_item.name_pattern)
    -- We should always have enough to insert.
    task_helpers.assert(slot ~= nil)
    --- @cast slot number

    -- Put it in
    wb:select(slot)
    local count = wb:getItemCount()
    task_helpers.assert(wb:dropDown(amount_needed)) -- This is okay to be nil

    -- Do we need to loop?
    if amount_needed ~= nil then
        amount_needed = amount_needed - count
        if amount_needed > 0 then goto need_more end
    end

    -- All done
    indexes.current_item_index = indexes.current_item_index + 1
    return true
end

--- Insert fuel if needed. Returns false if we're out of fuels.
--- @param task TurtleTask
--- @param indexes SmeltingIndexes
--- @return boolean
function maybe_refuel(task, indexes)
    local wb = task.walkback
    local task_data = task.definition.task_data
    local current_index = indexes.current_fuel_index
    --- @cast task_data SmeltingData

    -- Do we need to add fuel?
    if furnace_slot_count(2) ~= nil then
        -- no
        return true
    end


    -- Out of fuels?
    if #task_data.fuels == current_index - 1 then
        -- Out of fuels to use
        return false
    end

    -- Need to add fuel. Go find it.
    while true do
        local current_fuel = task_data.fuels[indexes.current_fuel_index]
        -- Out of fuels?
        if current_fuel == nil then
            return false
        end

        -- Find the item
        local slot = wb:inventoryFindPattern(current_fuel)

        -- Anything there?
        if slot == nil then
            -- Need to try the next fuel.
            indexes.current_fuel_index = indexes.current_fuel_index + 1
            goto continue
        else
            -- Select it and put it in.
            wb:select(slot)
            insert_fuel_item(wb)
            break
        end
        ::continue::
    end

    -- All done.
    -- Fuel index is incremented in the loop.
    return true
end



--- Smelts some items.
---
--- Returns a none result unless it fails.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function smelt_task(config)
    local wb = config.walkback

    -- Keep track of what inventory slot we started with
    local original_slot = wb:getSelectedSlot()

    -- Right task?
    if config.definition.task_data.name ~= "smelt_task" then
        task_helpers.throw("bad config")
    end

    -- This must be the right task.
    local task_data = config.definition.task_data
    --- @cast task_data SmeltingData

    -- Have stuff to do?
    if #task_data.to_smelt == 0 then
        -- Need to smelt something bud
        task_helpers.throw("bad config")
    end

    -- Need a fuel source
    if #task_data.fuels == 0 then
        -- Can't smelt nothin!
        task_helpers.throw("bad config")
    end

    -- Do we have a furnace?
    local furnace_slot = wb:inventoryFindPattern(FURNACE_PATTERN)
    if furnace_slot == nil then
        -- Need that...
        task_helpers.throw("assumptions not met")
    end

    -- Furnace exists.
    --- @cast furnace_slot number
    wb:select(furnace_slot)

    -- Do we actually have the requested items and fuels?

    -- Items
    for _, item in ipairs(task_data.to_smelt) do
        -- Find the item
        local found = wb:inventoryFindPattern(item.name_pattern)
        if found == nil then
            task_helpers.throw("bad config")
        end
        ---@cast found number

        -- Do we have enough of that item?
        if wb:getItemCount(found) < (item.limit or 0) then
            -- Not enough
            task_helpers.throw("bad config")
        end
    end

    -- For fuels we have no count, we just check that they exist
    for _, fuel in ipairs(task_data.fuels) do
        if not wb:inventoryFindPattern(fuel) then
           -- Fuel missing. You can only pass fuels you have.
           task_helpers.throw("bad config")
        end
    end

    -- We have the items and fuel.
    -- Place the furnace. Any movement will be automatically walked if needed
    -- back when the test ends
    if wb:inspectDown() then
        -- Need to go up.
        if wb:inspectUp() then
            -- ...But we cant.
            task_helpers.throw("assumptions not met")
        end
        -- If moving or placing fails, that can be automatically cleaned up.
        task_helpers.assert(wb:up())
        -- We already selected the furnace slot
        task_helpers.assert(wb:placeDown())
    else
        -- Nothing below us. Should be safe to place
        task_helpers.assert(wb:placeDown())
    end

    -- Wrap the furnace
    --- @diagnostic disable-next-line: undefined-global
    FURNACE_PERIPHERAL = peripheral.wrap("bottom")

    -- That should always work
    task_helpers.assert(FURNACE_PERIPHERAL ~= nil)

    -- Keep track of what item and what fuel we're using in the lists
    -- This is a table so we can pass it around
    --- @class SmeltingIndexes
    --- @field current_item_index number
    --- @field current_fuel_index number
    --- @private -- Just for us please.
    local indexes = {
        current_item_index = 1,
        current_fuel_index = 1
    }

    -- We do not know the fuel values of items, so we will just add the entire
    -- stack of fuel into the fuel slot

    -- TODO: Check if we are trying to smelt something un-smelt-able.

    -- Now for the fun part.
    while true do
        -- Add the next item if needed
        if not add_next_item(config, indexes) then
            -- Are we out of things to smelt?
            local slot_count = furnace_slot_count(1)
            if slot_count == nil then
                -- All done!
                break
            end
            -- Need to keep waiting, or refuel
        end

        -- Refuel if needed.
        if not maybe_refuel(config, indexes) then
            -- Out of fuels. We cannot continue.
            task_helpers.assert(wb:digDown())
            task_helpers.throw("assumptions not met")
        end

        -- Items take 10 seconds to smelt. We will wake up after the current set
        -- of items has finished smelting. (plus a little bit for leeway with lag)
        local count = furnace_slot_count(1)
        task_helpers.assert(count ~= nil)

        task_helpers.taskSleep((count * 10) + 2)

        -- Move out the resulting items if we can
        local empty_slot = wb:FindEmptySlot()
        if empty_slot == nil then
            task_helpers.throw("inventory full")
        end
        ---@cast empty_slot number

        wb:select(empty_slot)
        if not pull_result(wb) then
            -- Ingredients are still smelting after waiting the full period of time.
            -- If we're lagging maybe? But anyways, if there are no resulting
            -- items at all, this item is un-smelt-able.
            local result_count = furnace_slot_count(3)
            if result_count == nil then
                -- Bad!
                wb:digDown()
                task_helpers.throw("assumptions not met")
            end
            --- @cast result_count number
            -- There are resulting items.
            -- Maybe we somehow added too many items.
            if (furnace_slot_count(1) or 0) + result_count > 64 then
                -- IDK how we did that, but pull out the ingredients then pull
                -- the results, and put the ingredient back again...
                wb:suckDown()
                local free_slot_2 = wb:FindEmptySlot()
                if free_slot_2 == nil then
                    task_helpers.throw("inventory full")
                end
                --- @cast free_slot_2 number
                wb:select(free_slot_2)
                task_helpers.assert(pull_result(wb))
                wb:select(empty_slot)
                task_helpers.assert(wb:dropDown())

                -- Now put the result in the right slot
                if not wb:swapSlots(free_slot_2, empty_slot) then
                    task_helpers.throw("inventory full")
                end
            end
            -- ??? no idea
            task_helpers.throw("assumptions not met")
        end

        -- Loop!
    end

    -- Done smelting, grab the furnace (which will also grab all of the items
    -- inside of it)
    task_helpers.assert(wb:digDown())

    -- Return none, since we must have smelted everything.
    return task_helpers.try_finish_task(config, {name = "none"})
end

return smelt_task