-- Create a new turtle in front of the current turtle, if possible.

local task_helpers = require("task_helpers")
local helpers = require("helpers")

--- The configuration for the mitosis task.
---
--- This task copies files over to a turtle item using a disk drive,
--- places the new turtle, gives the new turtle some fuel, its pickaxe,
--- then turns it on.
---
--- Assumptions this task makes:
--- - There is a free space in front of the turtle to place the disk drive and
---   the new turtle.
--- - The turtle has all of the required items to create the new turtle in its
---   inventory.
---   - A turtle, diamond pickaxe, one of the allowed fuels, a disk drive
---
--- Task completion states:
--- - Huzzah! A turtle is born!
---
--- Task failure states:
--- - One of the assumptions is not met.
---
--- Notes:
--- - No timeout.
--- - Returns NoneResult.
--- @class MitosisData
--- @field name "mine_to_level"


--- Fuels that can be used for the new turtle, and their fuel values. Ordered by
--- preference.
---
--- We use the fuel values to calculate how many items we need to put in the new
--- turtle to start the new turtle with 1000 fuel.
--- @class MitosisValidFuel
--- @field name_pattern string
--- @field fuel_value number

--- @type MitosisValidFuel[]
local valid_fuels = {
    {
        name_pattern = "minecraft:coal",
        fuel_value = 80
    },
    {
        name_pattern = "minecraft:charcoal",
        fuel_value = 80
    },
    {
        name_pattern = "planks$",
        fuel_value = 15
    },
    { -- Planks have higher priority than logs since they give the same amount of fuel.
        name_pattern = "log$",
        fuel_value = 15
    },
}

--- Mine through the world till a desired Y level is hit.
--- @param config TurtleTask
--- @return TaskCompletion|TaskFailure
local function mitosis(config)
    local wb = config.walkback
    -- local task_data = config.definition.task_data
    -- Right task?
    if config.definition.task_data.name ~= "mine_to_level" then
        task_helpers.throw("bad config")
    end
    -- --- @cast task_data MineToLevelData

    -- Do we enough valid fuels?
    local fuel_sum = 0
    for _, fuel in ipairs(valid_fuels) do
        local count = wb:inventoryCountPattern(fuel.name_pattern)
        fuel_sum = fuel_sum + (count * fuel.fuel_value)
    end

    if fuel_sum < 1000 then
        -- Not enough.
        task_helpers.throw("assumptions not met")
    end

    -- Do we have the other items we need?
    -- Turtle
    if wb:inventoryCountPattern("computercraft:turtle_normal") < 1 then
        task_helpers.throw("assumptions not met")
    end

    -- Pick?
    if wb:inventoryCountPattern("minecraft:diamond_pickaxe") < 1 then
        task_helpers.throw("assumptions not met")
    end

    -- Drive?
    if wb:inventoryCountPattern("computercraft:disk_drive") < 1 then
        task_helpers.throw("assumptions not met")
    end

    -- We have everything we need.
    -- Is the space in front of us clear?
    if wb:detect() then
        task_helpers.throw("assumptions not met")
    end

    -- To make the turtle's disk mountable, we have to first place, turn on, and
    -- break the turtle again to give it a turtle id.
    -- Place the turtle
    local slot = wb:inventoryFindPattern("computercraft:turtle_normal")
    task_helpers.assert(slot ~= nil)
    --- @cast slot number

    wb:select(slot)
    task_helpers.assert(wb:place())

    -- Now wrap the turtle to turn it on
    ---@diagnostic disable-next-line: undefined-global
    local a = peripheral.wrap("front")
    task_helpers.assert(a ~= nil)
    -- Turn it on and off again.
    a.turnOn()
    a.shutdown()

    -- Now we can pick it up. Unsafe needs to be set since we're breaking a turtle.
    a = nil
    task_helpers.assert(wb:dig(nil, true))

    -- Time to copy files.

    -- Place the disk drive
    local slot = wb:inventoryFindPattern("computercraft:disk_drive")
    task_helpers.assert(slot ~= nil)
    --- @cast slot number

    wb:select(slot)
    task_helpers.assert(wb:place())

    -- Put in the turtle
    slot = wb:inventoryFindPattern("computercraft:disk_drive")
    task_helpers.assert(slot ~= nil)
    --- @cast slot number

    wb:select(slot)
    task_helpers.assert(wb:drop(1))

    -- Wrap the drive and get the mount path of the drive
    --- @type table|nil
    ---@diagnostic disable-next-line: undefined-global
    local drive = peripheral.wrap("front")
    task_helpers.assert(drive ~= nil)
    --- @cast drive table

    --- @type string|nil
    local mount_point = drive.getMountPath()
    task_helpers.assert(mount_point ~= nil)
    --- @cast mount_point string

    -- Now copy everything, luckily the fs.copy method works with directories,
    -- we just have to skip `rom` and the mount path of the disk drive.
    --- @type string[]
    ---@diagnostic disable-next-line: undefined-global
    local paths = fs.list("")

    for _, path in ipairs(paths) do
        local worked = false
        if path == mount_point or path == "rom" or path == "hello_world.json" then
            goto continue
        end

        -- Copy it over.
        ---@diagnostic disable-next-line: undefined-global
        worked, _ = pcall(fs.copy, path, mount_point .. "/" .. path)
        task_helpers.assert(worked)
        ::continue::
    end

    -- Now finally, we need to create the hello_world file to tell the new turtle
    -- where it is. The new turtle inherits our facing direction.
    local our_pos = wb.cur_position.position
    local our_facing = wb.cur_position.facing
    local new_pos = helpers.getAdjacentBlock(our_pos, our_facing, "f")

    --- @type HelloWorld
    local hello = {
        new = true,
        position = {position = new_pos, facing = our_facing}
    }

    --  Serialize that and put it on the turtle
    local cereal = helpers.serializeJSON(hello)

    ---@diagnostic disable-next-line: undefined-global
    local file = fs.open(mount_point .. "/" .. "hello_world.json", "wa")

    file.write(cereal)
    file.flush()
    file.close()

    -- Done putting on files, digging will pick up the drive and the contents.
    -- Unsafe since its a disk drive.
    task_helpers.assert(wb:dig(nil, true))

    -- Now place the turtle again
    local slot = wb:inventoryFindPattern("computercraft:turtle_normal")
    task_helpers.assert(slot ~= nil)
    --- @cast slot number

    wb:select(slot)
    task_helpers.assert(wb:place())

    -- Find fuels and put them in.
    local fuel_added = 0
    while fuel_added < 1000 do
        for _, fuel in ipairs(valid_fuels) do
            if fuel_added >= 1000 then break end
            local desire = 1000 - fuel_added
            local to_add = 0
            local amount_in_slot = 0
            local fuel_slot = wb:inventoryFindPattern(fuel.name_pattern)
            if fuel_slot == nil then
                goto skip_fuel
            else
                amount_in_slot = wb:getItemCount(fuel_slot)
            end

            -- Calculate how much of this item we need to add.
            to_add = math.min(math.ceil(desire / fuel.fuel_value), amount_in_slot)

            -- Select the slot and drop the items in.
            wb:select(fuel_slot)
            task_helpers.assert(wb:drop(to_add))

            -- Update the total
            fuel_added = fuel_added + (to_add * fuel.fuel_value)
            ::skip_fuel::
        end
    end

    -- Put in the pickaxe
    local pick_slot = wb:inventoryFindPattern("minecraft:diamond_pickaxe")
    task_helpers.assert(pick_slot ~= nil)
    --- @cast pick_slot number

    wb:select(pick_slot)
    task_helpers.assert(wb:drop())

    -- Turtle is ready! Turn it on!
    --- @type table|nil
    ---@diagnostic disable-next-line: undefined-global
    local turtle_peripheral = peripheral.wrap("front")
    task_helpers.assert(turtle_peripheral ~= nil)
    --- @cast turtle_peripheral table

    turtle_peripheral.a.turnOn()

    -- All done!
    return task_helpers.try_finish_task(config, {name = "none"})
end


return mitosis