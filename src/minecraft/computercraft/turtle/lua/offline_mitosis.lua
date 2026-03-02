-- This is only for the first video. Once we have server control of the turtles,
-- we can divvy out these tasks there. But for now, we need to deduce our next
-- step in creating new turtles based entirely on internal state.
-- Yes this is VERY dumb. But it is simple!

local helpers = require("helpers")
local task_helpers = require("task_helpers")

local finished_bootstrap = false

-- Common tasks to reduce duplication
--- @type TaskDefinition
local find_log = {
    fuel_buffer = 10,
    return_to_facing = false,
    return_to_start = false,
    --- @type BlockSearchData
    task_data = {
        name = "block_search",
        to_find = {
            names_patterns = {"log$"},
            tags = {},
        },
        fuel_items = {
            patterns = {
                "coal", "plank", "log"
            }
        }
    }
}

--- @type TaskDefinition
local tree_chop = {
    fuel_buffer = 100,
    return_to_facing = false,
    return_to_start = false,
    --- @type TreeChopTaskData
    task_data = {
        name = "tree_chop",
        timeout = 10000000000000, -- 'till you're done bud.
        target_logs = 64, -- a whole stack pwease.
        max_saplings = 16,
        min_saplings = 3
    }
}

--- @type TaskDefinition
local craft_eight_planks = {
    fuel_buffer = 0,
    return_to_facing = false,
    return_to_start = false,
    --- @type CraftingData
    task_data = {
        name = "craft_task",
        count = 2,
        recipe = {
            shape = {
                "log", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }
        }
    }
}

--- @type TaskDefinition
local craft_one_chest = {
    fuel_buffer = 0,
    return_to_facing = false,
    return_to_start = false,
    --- @type CraftingData
    task_data = {
        name = "craft_task",
        count = 1,
        recipe = {
            shape = {
                "planks", "planks", "planks",
                "planks", "BLANK", "planks",
                "planks", "planks", "planks",
            }
        }
    }
}

--- @type TaskDefinition
local fly_down = {
    fuel_buffer = 100,
    return_to_facing = false,
    return_to_start = false,
    --- @type MineToLevelData
    task_data = {
        name = "mine_to_level",
        level = 3,
    }
}

--- @type TaskDefinition
local fly_up = {
    fuel_buffer = 100,
    return_to_facing = false,
    return_to_start = false,
    --- @type MineToLevelData
    task_data = {
        name = "mine_to_level",
        level = 100,
    }
}



--- @param wb WalkbackSelf
--- @return boolean
function yoIsThatALog(wb)
    local front_block = wb:inspect()
    return front_block ~= nil and helpers.findString(front_block.name, "log")
end

--- Spins up to 4 times trying to find a log in front of the turtle.
--- Returns true if now facing a log, false otherwise.
--- @param wb WalkbackSelf
--- @return boolean
local function tryFaceLog(wb)
    for _ = 1, 4 do
        if yoIsThatALog(wb) then
            return true
        end
        wb:turnRight()
    end
    return false
end

--- Try to ensure that the log we are looking at is the base of a tree.
--- Not very rigorous but yeah. Just needs to work for now.
---
--- Returns true if we're in a good position.
---
--- Assumes we're already next to a tree
--- @param wb WalkbackSelf
--- @return boolean
local function faceBaseLog(wb)
    if not tryFaceLog(wb) then
        return false
    end

    -- Now move down until we hit the floor
    while not wb:detectDown() do
        wb:down()
    end

    -- Are we still next to a log?
    return tryFaceLog(wb)
end

--- Returns tasks needed to find and chop a tree.
--- Set fly up flag if you know the Y level is known, and you could be underground.
---
--- @param wb WalkbackSelf
--- @param may_fly boolean
--- @return TaskDefinition[]
local function findAndChopTree(wb, may_fly)
    -- Are we already next to a tree?
    if faceBaseLog(wb) then
        -- yes!
        return {tree_chop}
    end

    local tasks = {}

    -- Fly up if needed
    if may_fly and wb.cur_position.position.y < 50 then
        tasks[#tasks+1] = fly_up
    end

    -- Look for a tree, then chop it
    tasks[#tasks+1] = find_log
    tasks[#tasks+1] = tree_chop
    return tasks
end

--- Returns task in the order that they should be completed, IE: 1, 2, 3.
--- @param wb WalkbackSelf
--- @return TaskDefinition[]
local function deduceNextTask(wb)
    -- A bunch of booleans to gate possible actions to take.
    local knows_y
    local has_disk_drive
    local has_turtle
    local has_computer
    local has_diamond_pick
    local stone_count
    local cobblestone_count
    local log_count
    local plank_count
    local stick_count
    local redstone_dust_count
    local diamond_count
    local sand_count
    local glass_count
    local glass_pane_count
    local chest_count
    local raw_iron_count
    local iron_ingot_count
    local charcoal_count
    -- local has_sapling
    local has_furnace
    local crafting_table_count
    local looking_at_log
    local has_disk_drive_ingredients
    local has_turtle_ingredients
    local has_computer_ingredients
    local has_diamond_pick_ingredients

    -- If we don't know our Y position, it'll be set to -10,000
    knows_y = wb.cur_position.position.y > -1000

    has_disk_drive = wb:inventoryCountPattern("disk_drive") > 0
    has_turtle = wb:inventoryCountPattern("turtle") > 0
    has_computer = wb:inventoryCountPattern("computer_normal") > 0
    has_diamond_pick = wb:inventoryCountPattern("diamond_pickaxe") > 0
    stone_count = wb:inventoryCountPattern("minecraft:stone")
    cobblestone_count = wb:inventoryCountPattern("cobblestone")
    log_count = wb:inventoryCountPattern("_log")
    plank_count = wb:inventoryCountPattern("planks")
    stick_count = wb:inventoryCountPattern(":stick$")
    redstone_dust_count = wb:inventoryCountPattern("redstone")
    diamond_count = wb:inventoryCountPattern("diamond")
    sand_count = wb:inventoryCountPattern("sand$")
    glass_count = wb:inventoryCountPattern("glass$")
    glass_pane_count = wb:inventoryCountPattern("glass_pane")
    -- We make 2 chests, one for making the turtle, one for crafting.
    chest_count = wb:inventoryCountPattern("chest")
    raw_iron_count = wb:inventoryCountPattern("raw_iron")
    iron_ingot_count = wb:inventoryCountPattern("iron_ingot")
    charcoal_count = wb:inventoryCountPattern("charcoal")
    -- has_sapling = wb:inventoryCountPattern("sapling") > 0
    has_furnace = wb:inventoryCountPattern("furnace") > 0
    crafting_table_count = wb:inventoryCountPattern("crafting_table")


    looking_at_log = false
    local front_block = wb:inspect()
    if front_block ~= nil then
        looking_at_log = helpers.findString(front_block.name, "log")
    end

    has_disk_drive_ingredients = (stone_count >= 7) and (redstone_dust_count >= 2)
    has_turtle_ingredients = (iron_ingot_count >= 7) and has_computer and (chest_count >= 2)
    has_computer_ingredients = (stone_count >= 7) and (redstone_dust_count >= 1) and (glass_pane_count >= 1)
    has_diamond_pick_ingredients = (diamond_count >= 3) and (stick_count >= 2)


    -- Pre-compact the inventory to try and keep things clean.
    -- Don't care if this actually does anything or not, we just want to at least
    -- try it.
    task_helpers.compactInventory(wb)

    --- @type string[]
    local things_we_want = {
        "log",
        "planks",
        "iron_ingot",
        "raw_iron",
        "diamond",
        "turtle",
        "computer_normal",
        "disk_drive",
        "chest",
        "crafting_table",
        "furnace",
        "charcoal",
        ":stone$",
        "glass",
        "redstone",
        "sapling",
    }


    -- Only want sand if we dont got glass pane
    if glass_pane_count == 0 then
        things_we_want[#things_we_want+1] = "sand"
    end

    -- Only want cobble if we dont already have stone or a furnace
    if stone_count < 7 or not has_furnace then
        things_we_want[#things_we_want+1] = "cobblestone"
    end

    -- Only want sticks if we dont already have a pickaxe
    if not has_diamond_pick then
        things_we_want[#things_we_want+1] = "stick"
    end

    -- Throw away anything we don't need, as inventory space is at a premium.
    -- We will try burning the items first, since we would be throwing them
    -- on the floor anyways.
    for i=1, 16 do
        local item = wb:getItemDetail(i)
        if item == nil then goto continue end
        for _, pattern in ipairs(things_we_want) do
            if helpers.findString(item.name, pattern) then
                goto continue
            end
        end
        -- don't need this.
        wb:select(i)
        wb:refuel()
        wb:dropUp()

        ::continue::
    end


    -- Now actually for some task stuff.

    -- Refuel if we need to, and if we can.
    while true do
        if wb:getFuelLevel() > 640 then break end
        local fueled = task_helpers.tryRefuelFromInventory(wb, {"coal", "plank", "log", "stick"})
        if not fueled then break end -- If we have nothing to refuel with then we have to just give up
    end

    local fuel_level = wb:getFuelLevel()

    -- This is stupid, but we will always break the block above us to be able to
    -- craft or smelt anywhere
    wb:digUp()

    -- Old if chain was stupid. Now we have a slightly less stupid order based on
    -- phases.

    -- We need a chest as soon as possible so we can convert logs into planks
    -- while chopping trees.
    -- Kill me for the indentation i dont care
    if
        chest_count == 0 and
        log_count >= 2
    then
        -- Need to fly down until there is a floor below us, we don't want to
        -- try and craft midair, dropping everything
        while not wb:detectDown() do wb:down() end

        -- Make a chest
        return {craft_eight_planks, craft_one_chest}
    end


    -- Bootstrap phase
    if finished_bootstrap then goto skip_bootstrap end

    -- Gather logs in big batches until we have enough to normalize our Y level.
    if not knows_y then

        -- Do we have enough fuel to normalize?
        if fuel_level >= 640 then
            -- Yep! Time to fly.
            --- @type TaskDefinition
            local up_we_go = {
                fuel_buffer = 100,
                return_to_facing = false,
                return_to_start = false,
                --- @type NormalizeHeightData
                task_data = {
                    name = "normalize_height",
                }
            }
            return {up_we_go}
        end

        -- Not enough fuel. Gather an entire stack of logs lol
        return findAndChopTree(wb, false)
    else
        -- We now know our Y level.
        -- However, we do not finish bootstrapping until we have 64 logs in our
        -- inventory, since we wanna have a good buffer before moving onto making
        -- charcoal and such.
        if log_count < 64 then
            -- More trees.
            -- Still no flying here, since we haven't been underground.
            return findAndChopTree(wb, false)
        end
        -- We can actually be done.
        finished_bootstrap = true
    end

    ::skip_bootstrap::
    -- We now know our Y level is set.

    -- Now we want to immediately the furnace, the crafting tables, and the
    -- chests we'll need later.

    -- Chests
    if chest_count < 2 then
        -- If we don't have a chest at all, we need to make sure we're on the
        -- floor somewhere.
        if chest_count == 0 then
            while not wb:detectDown() do wb:down() end
        end

        -- Craft the chest
        if plank_count >= 8 then
            return {craft_one_chest}
        elseif log_count >= 2 then
            return {craft_eight_planks, craft_one_chest}
        else
            -- Need more tree.
            return findAndChopTree(wb, true)
        end
    end

    -- Furnace
    if not has_furnace then
        if cobblestone_count >= 8 then
            local craft_furnace = {
                fuel_buffer = 0,
                return_to_facing = false,
                return_to_start = false,
                --- @type CraftingData
                task_data = {
                    name = "craft_task",
                    count = 1,
                    recipe = {
                        shape = {
                            "cobblestone", "cobblestone", "cobblestone",
                            "cobblestone", "BLANK", "cobblestone",
                            "cobblestone", "cobblestone", "cobblestone",
                        }
                    }
                }
            }
            return {craft_furnace}
        else
            -- No cobblestone? We need to make a furnace before starting
            -- bigger mining trips, since we obviously want to burn charcoal and
            -- not logs.
            -- So we fly down to get cobblestone.
            return {fly_down}
        end
    end

    -- Crafting tables
    -- We only need 1, but crafting extra is fine. Since we craft eight planks
    -- at a time, we'll just make 2
    if crafting_table_count < 2 then
        local craft_table = {
            fuel_buffer = 0,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "planks", "planks", "BLANK",
                        "planks", "planks", "BLANK",
                        "BLANK", "BLANK", "BLANK",
                    }
                }
            }
        }
        if plank_count >= 8 then
            return {craft_table}
        elseif log_count >= 2 then
            return {craft_eight_planks, craft_table}
        else
            -- Need more tree.
            return findAndChopTree(wb, true)
        end
    end

    -- Now have all of the basic crafting related items.

    -- Smelt things if we need to.
    if has_furnace then
        -- Things we want to smelt
        --- @type SmeltItem[]
        local to_smelt = {}

        -- Charcoal?
        if charcoal_count < 32 then
            -- If we're out of charcoal completely, we have to save at least
            -- one log to burn for fuel.
            -- Overshoot a bit.
            local logs_to_burn = math.min(40 - charcoal_count, log_count)
            if charcoal_count == 0 then
                logs_to_burn = logs_to_burn - 1
            end
            --- @type SmeltItem
            local charcoal = {
                name_pattern = "log",
                limit = logs_to_burn
            }

            -- Make sure there is actually something to do
            if logs_to_burn > 0 then
                to_smelt[#to_smelt+1] = charcoal
            else
                -- Not enough logs. We need a tree.
                return findAndChopTree(wb, true)
            end
        end

        -- Stone?
        local desired_stone = 14 - stone_count
        if has_computer then desired_stone = desired_stone - 7 end
        if has_disk_drive then desired_stone = desired_stone - 7 end
        if desired_stone > 0 and cobblestone_count > 0 then
            --- @type SmeltItem
            local stone = {
                name_pattern = ":cobblestone$",
                limit = math.min(desired_stone, cobblestone_count)
            }
            to_smelt[#to_smelt+1] = stone
        end

        -- Iron?
        if raw_iron_count > 0 then
            --- @type SmeltItem
            local raw_iron = {
                name_pattern = "raw_iron",
                -- No limit, smelt all of it.
            }
            to_smelt[#to_smelt+1] = raw_iron
        end

        -- Glass?
        local desired_glass = 6
        if glass_pane_count > 0 then desired_glass = 0 end
        desired_glass = desired_glass - glass_count
        if desired_glass > 0 and sand_count > 0 then
            --- @type SmeltItem
            local sand = {
                name_pattern = "sand$",
                -- all of it.
            }
            to_smelt[#to_smelt+1] = sand
        end

        -- Anything to do?
        if #to_smelt > 0 then
            -- Smelt time!
            --- @type TaskDefinition
            local smelt_stuff = {
                fuel_buffer = 100,
                return_to_facing = false,
                return_to_start = false,
                --- @type SmeltingData
                task_data = {
                    name = "smelt_task",
                    to_smelt = to_smelt,
                    fuels = {"coal", "planks", "log"}
                }
            }
            return {smelt_stuff}
        end
    end



    if (fuel_level > 500) and (not has_turtle) and (not has_disk_drive) then
        -- Deduce if we need to go mining for any of the ingredients for things.
        --- @type { group: BlockGroup, desired_total: number }[]
        local groups_to_use = {}

        -- Iron?
        if not has_turtle and (raw_iron_count + iron_ingot_count < 7) then
            -- Need iron.
            --- @type { group: BlockGroup, desired_total: number }
            local iron = {
                desired_total = 7 - raw_iron_count - iron_ingot_count,
                group = {
                    names_patterns = {
                        "iron_ore$"
                    },
                    tags = {}
                }
            }
            groups_to_use[#groups_to_use+1] = iron
        end

        -- Redstone?
        -- Redstone ore always gives at least 4 dust.
        local wanted_dust = 3
        if has_computer then wanted_dust = wanted_dust - 1 end
        if has_disk_drive then wanted_dust = wanted_dust - 2 end
        wanted_dust = wanted_dust - redstone_dust_count

        if wanted_dust > 0 then
            -- Always mine just one.
            local redstone = {
                desired_total = 1,
                group = {
                    names_patterns = {
                        "redstone_ore$"
                    },
                    tags = {}
                }
            }
            groups_to_use[#groups_to_use+1] = redstone
        end

        -- Diamonds?
        if (not has_diamond_pick) and diamond_count < 3 then
            local diamond = {
                desired_total = 3 - diamond_count,
                group = {
                    names_patterns = {
                        "diamond_ore$"
                    },
                    tags = {}
                }
            }
            groups_to_use[#groups_to_use+1] = diamond
        end

        -- Do we actually want to mine anything?
        if #groups_to_use > 0 then
            -- Yes!

            ---@type TaskDefinition
            local miner_task = {
                fuel_buffer = 200, -- Just to get back up to the surface.
                return_to_facing = false,
                return_to_start = false, -- Don't care where we end up.
                ---@type BranchMinerData
                task_data = {
                    trunk_length = nil, -- Just keep going.
                    name = "branch_miner",
                    desired = {
                        groups = groups_to_use
                    },
                    discardables = { patterns = {
                        "dirt",
                        "gravel",
                        "diorite",
                        "andesite",
                        "granite",
                        "tuff",
                        "deepslate",
                        "amethyst",
                        "calcite",
                        "basalt",
                        "cobble", -- Discard last since we might still want it.
                    } },
                    fuel_items = { patterns = {"coal"} }, -- This matches charcoal
                    incidental = {
                        groups = {
                            {
                                names_patterns = {
                                    "stone",
                                    "dirt",
                                    "gravel",
                                    "diorite",
                                    "andesite",
                                    "granite",
                                    "deepslate",
                                    "tuff",
                                    "amethyst",
                                    "calcite",
                                    "basalt",
                                },
                                tags = {}
                            }
                        }
                    }
                },
            }

            -- Mine down if needed.
            if wb.cur_position.position.y ~= 3 then
                return {fly_down, miner_task}
            else
                return {miner_task}
            end
        end
    end

    -- Get sand if we need it.
    if
        has_disk_drive and
        not has_computer and
        stone_count >= 7 and
        redstone_dust_count >= 1 and
        glass_pane_count == 0 and
        glass_count < 6 and
        sand_count < 6
    then
        -- find
        local find_sand = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type BlockSearchData
            task_data = {
                name = "block_search",
                to_find = {
                    names_patterns = {"sand$"},
                    tags = {},
                },
                fuel_items = {
                    patterns = {
                        "coal"
                    }
                }
            }
        }

        -- mine
        local mine_sand = {
            fuel_buffer = 0,
            return_to_facing = true,
            return_to_start = true,
            ---@type RecursiveMinerData
            task_data = {
                name = "recursive_miner",
                timeout = nil,
                blocks_mined_limit = 6 - sand_count,
                fuel_patterns = {
                    "coal", "plank", "log"
                },
                mineable_groups = {
                    {
                        names_patterns = {"sand$"},
                        tags = {},
                    }
                },
                discardables = {
                    patterns = {
                        "dirt",
                        "gravel",
                        "diorite",
                        "andesite",
                        "granite",
                        "tuff",
                        "deepslate",
                        "amethyst",
                        "calcite",
                        "basalt",
                        "cobble",
                    }
                }
            },
        }


        -- Go above ground if needed.
        if wb.cur_position.position.y < 64 then
            return {fly_up, find_sand, mine_sand}
        else
            return {find_sand, mine_sand}
        end
    end



    -- Craft stuff
    local craft_template = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        --- @type CraftingData
        task_data = {
            name = "craft_task",
            count = 1,
            --- Fill this in down lower.
            recipe = {
                shape = {}
            }
        }
    }

    -- Pickaxe
    -- Only make sticks and planks for it if we already have the diamonds, and
    -- we dont already have a pick

    -- Sticks
    if not has_diamond_pick and diamond_count >= 3 then
        -- Do we have sticks?
        if stick_count < 2 then
            -- No. Do we have planks?
            if plank_count < 2 then
                -- Need planks.
                -- I love nesting
                if log_count == 0 then
                    -- No logs is craaazy
                    return findAndChopTree(wb, true)
                end
                -- Make the planks
                craft_template.task_data.recipe.shape = {
                    "log$", "BLANK", "BLANK",
                    "BLANK", "BLANK", "BLANK",
                    "BLANK", "BLANK", "BLANK"
                }
                return {craft_template}
            end
            -- We have planks. Make the sticks,
            craft_template.task_data.recipe.shape = {
                "planks$", "BLANK", "BLANK",
                "planks$", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK"
            }
            return {craft_template}
        end

        -- Got it all. Make the pick
        craft_template.task_data.recipe.shape = {
            "diamond", "diamond", "diamond",
            "BLANK", "stick", "BLANK",
            "BLANK", "stick", "BLANK"
        }
        return {craft_template}
    end

    -- Panes
    if glass_count >= 6 then
        -- Make panes
        craft_template.task_data.recipe.shape = {
            "glass$", "glass$", "glass$",
            "glass$", "glass$", "glass$",
            "BLANK", "BLANK", "BLANK"
        }
        return {craft_template}
    end

    -- Disk Drive
    if has_disk_drive_ingredients and not has_disk_drive then
        craft_template.task_data.recipe.shape = {
            ":stone", ":stone", ":stone",
            ":stone", "redstone", ":stone",
            ":stone", "redstone", ":stone"
        }
        return {craft_template}
    end

    -- Computer
    if has_computer_ingredients and not has_computer then
        craft_template.task_data.recipe.shape = {
            ":stone", ":stone", ":stone",
            ":stone", "redstone", ":stone",
            ":stone", "glass_pane", ":stone"
        }
        return {craft_template}
    end

    -- Turtle
    if has_turtle_ingredients and not has_turtle then
        craft_template.task_data.recipe.shape = {
            "iron_ingot$", "iron_ingot$", "iron_ingot$",
            "iron_ingot$", "computer_normal$", "iron_ingot$",
            "iron_ingot$", "chest", "iron_ingot$"
        }
        return {craft_template}
    end

    -- We must now have everything we need to make a new turtle.
    -- We only collect enough for one turtle at a time (besides glass panes) which
    -- means we have to do a mining trip after every mitosis, so its reasonable to
    -- assume we must have gotten enough stone for crafting. We don't explicitly
    -- go mining for it.


    -- Find a tree and split.

    -- Are we next to a tree?
    if faceBaseLog(wb) then
        -- Yes. Do the mitosis.
        --- @type TaskDefinition
        local mitosis = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type MitosisData
            task_data = {
                name = "mitosis_task"
            }
        }

        -- Make sure there is room behind us. This should always be the case, but
        -- you never know.
        wb:turnRight()
        wb:turnRight()
        wb:dig()
        wb:turnRight()
        wb:turnRight()
        return {mitosis}
    else
        -- Not next to a tree yet. Go find one.
        return {find_log}
    end

end

return deduceNextTask