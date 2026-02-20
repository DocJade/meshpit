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
--- If you want to smelt more than one stack of the same item, you cannot set a
--- smelting limit. Thus you can only smelt at most one stack at a time if you
--- want to control how much you're smelting.
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
        if not found then
            task_helpers.throw("bad config")
        end
        ---@cast found number

        -- Do we have enough of that item?
        if wb:getItemCount(found) < item.limit or 0 then
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

    -- Now for the fun part.
    while true do
        -- Add the next item if needed
        if not add_next_item() then
            -- Out of things to smelt! We're done!
            break
        end

        -- Refuel if needed.
        if not do_refuel() then
            -- Out of fuels. We cannot continue.
            task_helpers.assert(wb:digDown())
            task_helpers.throw("assumptions not met")
        end

        -- Items take 10 seconds to smelt. We will wake up after the current set
        -- of items has finished smelting. (plus a little bit for leeway with lag)
        local count = count_smelting()
        task_helpers.assert(count ~= nil)

        task_helpers.taskSleep((count * 10) + 2)

        -- Move out the result
        take_result()

        -- Loop!
    end

    -- Done smelting, grab the furnace (which will also grab all of the items
    -- inside of it)
    task_helpers.assert(wb:digDown())

    -- Return none, since we must have smelted everything.
    return task_helpers.try_finish_task(config, {name = "none"})
end




return smelt_task