-- Craft items based on passed recipes, and automatically manages inventories
-- accordingly.

local task_helpers = require("task_helpers")
local helpers = require("helpers")


--- The layout for a crafting recipe. Uses pattern matching for the names of the
--- items.
---
--- Recipies must have no nil slots. If the length of the array is NOT 9, the
--- recipe will be assumed invalid. If you need a blank spot, use "BLANK"
---
--- @class CraftingRecipe
--- @field shape string[]|"BLANK"[]

--- The configuration for the crafting task
---
--- We assume there is space in our inventory for all of the resulting items.
--- Thus, please dont craft a stack of shovels i am begging you.
---
--- We also assume there is a crafting table in the inventory of the turtle,
--- a chest may be provided to move the inventory into if there are extra items.
--- If no chest is present, the crafting will be performed by throwing items onto
--- the floor under the turtle. This is obviously not preferred, so don't do that
--- whenever possible.
---
--- We assume that there is no block below us when crafting. We use that spot
--- for placing the chest and interacting with its storage, or if we do not
--- have a chest, throwing items on the ground. If the spot is not empty, the
--- task will attempt to move upwards to make room. The block below the turtle
--- must be a full block, otherwise dropped items may slide away.
---
--- The final crafted item (or at least one stack of them) will be moved into
--- slot 1.
---
--- If `move_inventory` is false and there is extra items in the inventory besides
--- the ingredients needed for the crafting recipe,
--- @class CraftingData
--- @field name "craft_task"
--- @field recipe CraftingRecipe -- What we crafting
--- @field count number -- How many to craft. This number is required. We only craft exact amounts.


--- Are we just throwing shit on the floor?
local squalor = true
local wrapped_chest = nil

--- The name of chests.
local CHEST_PATTERN = "minecraft:chest"

--- The name of crafting tables.
local CRAFTING_TABLE_PATTERN = "minecraft:crafting_table"

--- Move an item slot out of our inventory, either onto the floor or into
--- the chest depending on how poor we are.
--- @param wb WalkbackSelf
--- @param slot number
function store_slot(wb, slot)
    -- This is always just dropDown since that would either drop it, or put it
    -- into the chest below us
    wb:select(slot)
    if not wb:dropDown() then
        -- ?? Out of room?
        task_helpers.throw("assumptions not met")
    end
end

--- Swap two slots in a chest. This sucks.
---
--- This assumes that there are empty slots in the chest.
--- @param slot1 number
--- @param slot2 number
function swap_chest_slots(slot1, slot2)
    -- Search through the chest for the first empty slot.
    local empty_slot = nil
    ---@diagnostic disable-next-line: need-check-nil, undefined-field
    for slot = 1, wrapped_chest.size() do
        ---@diagnostic disable-next-line: need-check-nil, undefined-field
        if wrapped_chest.getItemDetail(slot) == nil then
            empty_slot = slot
            break
        end
    end

    -- Found space?
    if empty_slot == nil then
        -- we dont try to pick up the chest or anything, since we wouldn't be
        -- able to hold its contents anyways.
        task_helpers.throw("assumptions not met")
    end

    -- Swap time. I hate this.
    -- I hate the naming scheme of this shit. Push... man
    ---@diagnostic disable-next-line: need-check-nil, undefined-field, undefined-global
    wrapped_chest.pushItems(peripheral.getName(wrapped_chest), slot1, nil, empty_slot)
    ---@diagnostic disable-next-line: need-check-nil, undefined-field, undefined-global
    wrapped_chest.pushItems(peripheral.getName(wrapped_chest), slot2, nil, slot1)
    ---@diagnostic disable-next-line: need-check-nil, undefined-field, undefined-global
    wrapped_chest.pushItems(peripheral.getName(wrapped_chest), empty_slot, nil, slot2)
end

--- Find an item we want and move it into slot 4 of our inventory. Returns false
--- if that item does not exist, or if slot 4 already has items in it.
--- @param wb WalkbackSelf
--- @param pattern string
--- @return boolean
function find_item(wb, pattern)
    if wb:getItemCount(4) > 0 then
        -- cant move into a full slot
        return false
    end

    -- If we are not poor, search the chest, otherwise skip to the silly part.
    if squalor then goto silly end

    -- Find the item in the chest
    ---@diagnostic disable-next-line: need-check-nil, undefined-field
    for slot, item in ipairs(wrapped_chest.list()) do
        if helpers.findString(item.name, pattern) then
            -- This is what we want. Take it.

            -- Also, there is NO DIRECT WAY TO PULL ITEMS OUT OF A SLOT INTO
            -- THE TURTLE??? so we have to do this swap bullshit.
            -- Pull the item we want into slot 1.
            swap_chest_slots(slot, 1)

            -- Now we know where it is, grab it.
            wb:select(4)
            task_helpers.assert(wb:suckDown())

            -- Done.
            return true
        end
    end

    -- Item not present.
    -- Need a block here or lua gets pissy
    if true then
        return false
    end

    ::silly::
    -- yes picking up stuff over and over off the floor sucks, but really if you're
    -- crafting, you should have a chest. This is only here for bootstrapping when
    -- we don't yet have one.

    wb:select(4)

    -- Suck up... something. See if it matches.
    -- We will try at most 50 times.
    for _=1, 50 do
        if not wb:suckDown() then
            -- Nothing to suck
            return false
        end
        local item = wb:getItemDetail(4)
        if item == nil then
            -- ???? sucked nothing somehow
            return false
        end
        if helpers.findString(item.name, pattern) then
            -- That what we want!
            return true
        end
        -- Nope, drop it.... drop it... hey i said drop it.... no treat!
        if not wb:dropDown() then
            -- ????? how
            return false
        end
    end

    -- Didn't find it.
    return false
end

--- Get all of our items back from wherever we stored them
--- @param wb WalkbackSelf
function sigma_hoarder_grindset(wb)
    -- Just suck till we cannot suck no more :FreakyCanny:
    while wb:suckDown() do
        -- run it again lol
    end
end

--- Fill in a position of the crafting recipe, automatically swapping out slot
--- 4 if needed.
---
--- Returns false if we are out of the ingredient that would go in that slot.
--- @param wb WalkbackSelf
--- @param ingredient_pattern string
--- @param count number
--- @return boolean
function place_slot(wb, ingredient_pattern, destination_slot, count)
    -- Do we have what we need?
    local go_fish = false
    local slot_4 = wb:getItemDetail(4)
    if slot_4 == nil then
        go_fish = true
    else
        -- Only have to go fishing if this is not the item we want
        go_fish = not helpers.findString(slot_4.name, ingredient_pattern)
    end

    if go_fish then
        -- Put away if needed
        if slot_4 ~= nil then
            store_slot(wb, 4)
        end

        -- get the new item
        if not find_item(wb, ingredient_pattern) then
            -- Couldn't find the item we needed.
            return false
        end
    end

    -- Slot 4 now has our item
    -- Place the amount we want in the desired slot
    if not wb:transferFromSlotTo(4, destination_slot, count) then
        -- Couldn't move for some reason.
        return false
    end

    -- All good!
    return true
end



--- Crafts a specified crafting recipe, doing inventory management as needed.
---
--- Returns a none result unless it fails.
---
--- This may equip a crafting table if needed, and the crafting table will NOT
--- be automatically un-equipped.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function craft_task(config)
    local wb = config.walkback

    -- Keep track of what inventory slot we started with
    local original_slot = wb:getSelectedSlot()


    -- Right task?
    if config.definition.task_data.name ~= "craft_task" then
        task_helpers.throw("bad config")
    end

    -- This must be the right task.
    local task_data = config.definition.task_data
    --- @cast task_data CraftingData

    -- right number of slots?
    if #task_data.recipe.shape ~= 9 then
        task_helpers.throw("bad config")
    end

    -- Do we have a crafting table, or is one already equipped?
    local equipped_left = (wb:getEquippedLeft() or {name = "cheeseburger"}).name
    local equipped_right = (wb:getEquippedRight() or {name = "cheeseburger"}).name

    local have_left = helpers.findString(equipped_left, CRAFTING_TABLE_PATTERN)
    local have_right = helpers.findString(equipped_right, CRAFTING_TABLE_PATTERN)

    if not (have_left or have_right) then
        -- Do we have one in the inventory?
        local table_slot = wb:inventoryFindPattern(CRAFTING_TABLE_PATTERN)
        if table_slot == nil then
            -- No table.
            task_helpers.throw("assumptions not met")
            -- Linter doesn't know this converges
            --- @cast table_slot number
        end

        wb:select(table_slot)

        -- Can we equip one?
        if equipped_left == "cheeseburger" then
            wb:equipLeft()
        elseif equipped_right == "cheeseburger" then
            wb:equipRight()
        else
            -- No free slot to equip it!
            print("couldn't equip!")
            task_helpers.throw("assumptions not met")
        end
    end



    -- Is the block below us empty?
    if wb:detectDown() then
        -- We aren't in a good spot. Can we move up?
        if wb:detectUp() then
            -- Can't do anything here.
            print("Block above!")
            task_helpers.throw("assumptions not met")
        end
        -- We can move up.
        -- If we need to return to the starting position, the task ender helper
        -- will automatically move us back down when we're done.
        if not wb:up() then
            -- Couldn't move up.
            print("Can't move up!")
            task_helpers.throw("assumptions not met")
        end
    end

    -- Spot is good. Do we have the items for this craft?
    -- We do not check quantities here. Other things will fail correctly later
    -- if we are short.
    for _, ingredient in ipairs(task_data.recipe.shape) do
        if ingredient == "BLANK" then goto skip end

        -- Find the item.
        if wb:inventoryFindPattern(ingredient) == nil then
            -- Missing.
            print("Missing ingredients!")
            task_helpers.throw("assumptions not met")
        end
        ::skip::
    end

    -- We have all the ingredients on hand.

    -- Do we have a chest?
    local chest_slot = wb:inventoryFindPattern(CHEST_PATTERN)
    if chest_slot ~= nil then
        -- We have a chest!
        print("Found chest!")
        squalor = false

        -- Place it
        wb:select(chest_slot)
        task_helpers.assert(wb:placeDown())

        -- This will auto unwrap when we move(?), the peripheral is destroyed(?)
        -- or when the variable falls out of scope(?)
        ---@diagnostic disable-next-line: undefined-global
        wrapped_chest = peripheral.wrap("bottom")
    end

    -- Now we can actually start crafting.
    -- Indexing here is fun since its a 3x3 in a 4x4 grid.

    -- Put all of our crap away
    for i=1, 16 do
        print("Putting crap away...")
        store_slot(wb, i)
    end

    -- Assemble ingredients
    -- yes im lazy and don't wanna think about the math right now

    for i=1, 3 do
        local pattern = task_data.recipe.shape[i]
        if pattern ~= "BLANK" then
            task_helpers.assert(place_slot(wb, pattern, i, task_data.count))
        end
    end

    for i= 4, 6 do
        local pattern = task_data.recipe.shape[i]
        if pattern ~= "BLANK" then
            task_helpers.assert(place_slot(wb, pattern, i + 1, task_data.count))
        end
    end

    for i= 7, 9 do
        local pattern = task_data.recipe.shape[i]
        if pattern ~= "BLANK" then
            task_helpers.assert(place_slot(wb, pattern, i + 2, task_data.count))
        end
    end

    -- Do the craft
    task_helpers.assert(wb:craft(task_data.count))

    -- Now move that crafted item (ends up in whatever slot is currently selected)
    -- into slot 1
    wb:swapSlots(wb:getSelectedSlot(), 1)

    -- Get all of our stuff back
    sigma_hoarder_grindset(wb)

    -- Pick up our chest if needed.
    if not squalor then
        task_helpers.assert(wb:digDown())
    end

    wb:select(original_slot)

    -- All done!
    --- @type NoneResult
    local result = {
        name = "none"
    }

    return task_helpers.try_finish_task(config, result)
end

return craft_task