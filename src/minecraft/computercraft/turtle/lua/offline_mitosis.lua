-- This is only for the first video. Once we have server control of the turtles,
-- we can divvy out these tasks there. But for now, we need to deduce our next
-- step in creating new turtles based entirely on internal state.
-- Yes this is dumb. But it is simple!

local helpers = require("helpers")
local task_helpers = require("task_helpers")

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
    local has_7_stone
    local has_cobblestone
    local has_2_log
    local has_2_planks
    local has_2_sticks
    local has_2_redstone
    local has_3_diamonds
    local has_sand
    local has_6_glass
    local has_glass_pane
    local has_2_chest
    local has_raw_iron
    local has_7_iron_ingot
    local has_32_charcoal
    local has_sapling
    local has_furnace
    local has_2_crafting_table
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
    has_7_stone = wb:inventoryCountPattern("minecraft:stone") >= 7
    has_cobblestone = wb:inventoryCountPattern("cobblestone") > 0
    has_2_log = wb:inventoryCountPattern("_log") >= 2
    has_2_planks = wb:inventoryCountPattern("planks") >= 2
    has_2_sticks = wb:inventoryCountPattern(":stick$") >= 2
    has_2_redstone = wb:inventoryCountPattern("redstone") >= 2
    has_3_diamonds = wb:inventoryCountPattern("diamond") >= 3
    has_sand = wb:inventoryCountPattern("sand$") > 0
    has_6_glass = wb:inventoryCountPattern("glass$") >= 6
    has_glass_pane = wb:inventoryCountPattern("glass_pane") > 0
    -- We make 2 chests, one for making the turtle, one for crafting.
    has_2_chest = wb:inventoryCountPattern("chest") >= 2
    has_raw_iron = wb:inventoryCountPattern("raw_iron") > 0
    has_7_iron_ingot = wb:inventoryCountPattern("iron_ingot") >= 7
    has_32_charcoal = wb:inventoryCountPattern("charcoal") >= 32
    has_sapling = wb:inventoryCountPattern("sapling") > 0
    has_furnace = wb:inventoryCountPattern("furnace") > 0
    has_2_crafting_table = wb:inventoryCountPattern("crafting_table") >= 2


    looking_at_log = false
    local front_block = wb:inspect()
    if front_block ~= nil then
        looking_at_log = helpers.findString(front_block.name, "log")
    end

    has_disk_drive_ingredients = has_7_stone and has_2_redstone
    has_turtle_ingredients = has_7_iron_ingot and has_computer and has_2_chest
    has_computer_ingredients = has_7_stone and has_2_redstone and has_glass_pane
    has_diamond_pick_ingredients = has_3_diamonds and has_2_sticks

    -- Common tasks to reduce duplication
    --- @type TaskDefinition
    local find_log = {
        fuel_buffer = 100,
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
    local craft_planks = {
        fuel_buffer = 100,
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


    -- Pre-compact the inventory to try and keep things clean.
    -- Don't care if this actually does anything or not, we just want to at least
    -- try it.
    task_helpers.compactInventory(wb)


    -- Now actually for some task stuff.

    -- Refuel if we need to, and if we can.
    while true do
        if wb:getFuelLevel() > 500 then break end
        local fueled = task_helpers.tryRefuelFromInventory(wb, {"coal", "plank", "log", "stick"})
        if not fueled then break end -- If we have nothing to refuel with then we have to just give up
    end

    -- Mitosis
    -- We want to start the new turtle facing a tree because we're nice.
    if has_disk_drive and has_turtle and has_diamond_pick and has_32_charcoal and has_2_crafting_table and knows_y then
        -- We can make a turtle!
        -- Make sure we're facing a tree, otherwise go find one.
        if not looking_at_log then
            -- Maybe we're just not facing it?
            local rotations = 4
            while rotations ~= 0 and not looking_at_log do
                wb:turnRight()
                local front_block = wb:inspect()
                if front_block ~= nil then
                    looking_at_log = helpers.findString(front_block.name, "log")
                end
                rotations = rotations - 1
            end
            -- Did we find one?
            if not looking_at_log then
                -- Need to go actually stand next to a tree.
                return {find_log}
            end
        end

        -- We're facing a tree. Ready to do this!
        -- Make sure we're on the ground
        if not wb:detectDown() then
            -- floating... move down until we hit the ground, then check again
            -- that there still is a tree in front of us.
            while not wb:detectDown() do
                wb:down()
                local front_block = wb:inspect()
                if front_block ~= nil then
                    looking_at_log = helpers.findString(front_block.name, "log")
                end
            end
            -- Make sure the log is still there
            if not looking_at_log then
                -- Well darn. Need to find another tree instead.
                -- This in theory could put us in a loop, so we will first turn
                -- around.
                wb:turnRight()
                wb:turnRight()
                return {find_log}
            end
        end

        -- Move back to make room for the turtle. If this doesn't work, we will have
        -- to do something else.
        if wb:back() then
            -- Run the task.
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
            return {mitosis}
        end
    end

    -- Fix the Y level?
    -- We need at least 10 charcoal or 40 logs for that, unless we already have enough fuel
    local charcoal_count = wb:inventoryCountPattern("charcoal")
    local log_count = wb:inventoryCountPattern("log")
    if (not knows_y) and ((charcoal_count >= 10) or (wb:getFuelLevel() > 800) or (log_count >= 40)) then
        while true do
            if wb:getFuelLevel() > 800 then break end
            task_helpers.tryRefuelFromInventory(wb, {"coal", "log"})
        end
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

    -- Make the turtle item?
    if (not has_turtle) and has_turtle_ingredients and has_2_chest then
        --- @type TaskDefinition
        local craft_turtle = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "iron_ingot", "iron_ingot", "iron_ingot",
                        "iron_ingot", "computer_normal", "iron_ingot",
                        "iron_ingot", "chest", "iron_ingot",
                    }
                }
            }
        }
        return {craft_turtle}
    end

    -- Make the computer?
    -- Dont make more computers while we already have a turtle ready.
    if (not has_computer) and (not has_turtle) and has_computer_ingredients and has_2_chest then
        --- @type TaskDefinition
        local craft_computer = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "minecraft:stone", "minecraft:stone", "minecraft:stone",
                        "minecraft:stone", "redstone", "minecraft:stone",
                        "minecraft:stone", "glass_pane", "minecraft:stone",
                    }
                }
            }
        }
        return {craft_computer}
    end

    -- Make the diamond pickaxe?
    if (not has_diamond_pick) and has_diamond_pick_ingredients and has_2_chest then
        --- @type TaskDefinition
        local craft_pick = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "diamond", "diamond", "diamond",
                        "BLANK", "stick", "BLANK",
                        "BLANK", "stick", "BLANK",
                    }
                }
            }
        }
        return {craft_pick}
    end

    -- Make sticks?
    -- Only make sticks if we already have the diamonds for the pick.
    if (not has_2_sticks) and has_2_planks and has_2_chest and has_3_diamonds and (not has_diamond_pick) then
        --- @type TaskDefinition
        local craft_stick = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "plank", "BLANK", "BLANK",
                        "plank", "BLANK", "BLANK",
                        "BLANK", "BLANK", "BLANK",
                    }
                }
            }
        }
        return {craft_stick}
    end

    -- Make planks?
    if (not has_2_planks) and has_2_log and has_2_chest then
        return {craft_planks}
    end

    -- Make the disk drive?
    -- Only make this if we already have the turtle.
    if (not has_disk_drive) and has_turtle and has_disk_drive_ingredients and has_2_chest then
        --- @type TaskDefinition
        local craft_drive = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "minecraft:stone", "minecraft:stone", "minecraft:stone",
                        "minecraft:stone", "redstone", "minecraft:stone",
                        "minecraft:stone", "redstone", "minecraft:stone",
                    }
                }
            }
        }
        return {craft_drive}
    end

    -- Make glass panes?
    -- Only make the glass panes if we have all of the other ingredients we need
    -- for the computer
    if (not has_glass_pane) and has_6_glass and has_2_chest and has_2_redstone and has_7_stone then
        --- @type TaskDefinition
        -- RIP Otto.
        local life_is_pane_i_hate = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "glass$", "glass$", "glass$",
                        "glass$", "glass$", "glass$",
                        "BLANK", "BLANK", "BLANK",
                    }
                }
            }
        }
        return {life_is_pane_i_hate}
    end


    -- Make crafting table?
    -- We need to have the chest to craft in already.
    if (not has_2_crafting_table) and has_2_log and has_2_chest then
        --- @type TaskDefinition[]
        local stuff_to_do = {}
        -- Only make the planks for the crafting table if we dont already
        -- have enough of them.
        if wb:inventoryCountPattern("planks") < 4 then
            stuff_to_do[#stuff_to_do+1] = craft_planks
        end

        -- Make the actual table
        local table_time = {
            fuel_buffer = 100,
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
        stuff_to_do[#stuff_to_do+1] = table_time

        return stuff_to_do
    end

    -- Have smooth stone for crafting?
    -- Only do this if we are ready to make the disk drive or computer, which both
    -- require redstone
    if (not has_7_stone) and has_cobblestone and has_furnace and has_32_charcoal and has_2_redstone then
        --- @type TaskDefinition
        local smelt_stone = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type SmeltingData
            task_data = {
                name = "smelt_task",
                to_smelt = {
                    {
                        name_pattern = "cobblestone",
                        limit = 7, -- only make just enough, don't wanna clog the inventory.
                    }
                },
                fuels = {"coal"}
            }
        }
        return {smelt_stone}
    end

    -- Have furnace for smelting?
    if (not has_furnace) and has_cobblestone and has_2_chest then
        -- Craft one
        --- @type TaskDefinition
        local craft_furnace = {
            fuel_buffer = 100,
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
    end

    -- Have chest for crafting / turtle?
    if (not has_2_chest) and has_2_log then
        -- This is the only crafting task that doesn't check for a chest to
        -- craft with, since it needs to be able to bootstrap.

        --- @type TaskDefinition[]
        local stuff_to_do = {}

        -- Only make planks if we need to.
        if wb:inventoryCountPattern("planks") < 8 then
            -- Craft twice.
            stuff_to_do[#stuff_to_do+1] = craft_planks
            stuff_to_do[#stuff_to_do+1] = craft_planks
        end

        -- Make the chest.
        --- @type TaskDefinition
        local craft_chest = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type CraftingData
            task_data = {
                name = "craft_task",
                count = 1,
                recipe = {
                    shape = {
                        "plank", "plank", "plank",
                        "plank", "BLANK", "plank",
                        "plank", "plank", "plank",
                    }
                }
            }
        }

        stuff_to_do[#stuff_to_do+1] = craft_chest

        return stuff_to_do
    end

    -- Iron to smelt?
    -- Only smelt it if we are ready to make the turtle. IE we already have redstone.
    if (not has_7_iron_ingot) and has_raw_iron and has_furnace and has_32_charcoal and has_2_redstone then
        --- @type TaskDefinition
        local smelt_iron = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type SmeltingData
            task_data = {
                name = "smelt_task",
                to_smelt = {
                    {
                        name_pattern = "raw_iron",
                        limit = nil, -- Just smelt all of it.
                    }
                },
                fuels = {"coal"}
            }
        }
        return {smelt_iron}
    end

    -- Smelt glass?
    -- Only do this if we already have the stone and the redstone to make the
    -- computer.
    if (not has_6_glass) and has_sand and has_32_charcoal and has_7_stone and has_2_redstone then
        --- @type TaskDefinition
        local smelt_glass = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type SmeltingData
            task_data = {
                name = "smelt_task",
                to_smelt = {
                    {
                        name_pattern = "sand$",
                        limit = nil, -- Just smelt all of it. Better to do bulk.
                    }
                },
                fuels = {"coal"}
            }
        }
        return {smelt_glass}
    end

    -- Make charcoal?
    if (not has_32_charcoal) and has_furnace and has_2_log then
        --- @type TaskDefinition
        local make_charcoal = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type SmeltingData
            task_data = {
                name = "smelt_task",
                to_smelt = {
                    {
                        name_pattern = "log",
                        limit = 16, -- Only make 16 at a time.
                    }
                },
                fuels = {"coal", "plank", "log"}
            }
        }
        return {make_charcoal}
    end

    -- Gather logs?
    if not has_2_log then
        -- Need to find a tree.
        if not looking_at_log then

            -- To prevent searching underground, we first want to make sure we're
            -- above ground. Since the search pattern falls to the ground after
            -- moving forwards, we can mine straight up and then start the search
            -- without worrying that the search will fall into the hole we just
            -- came out of.
            -- 100 should be above the surface on average. Good enough.
            if wb.cur_position.position.y < 100 and knows_y then
                -- Go up
                return {fly_up}
            end


            --- @type TaskDefinition
            local find_log = {
                fuel_buffer = 100,
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
            return {find_log}
        end
        -- Next to log. Are we on the floor?
        if not wb:detectDown() then
            -- Move down to the floor
            while not wb:detectDown() do
                wb:down()
            end
            -- Return, since we will get re-ran in the right spot now.
            return {}
        end

        -- On the floor in front of a log, we can tree it now.
        --- @type TaskDefinition
            local tree_chop = {
            fuel_buffer = 100,
            return_to_facing = false,
            return_to_start = false,
            --- @type TreeChopTaskData
            task_data = {
                name = "tree_chop",
                timeout = 10000000000000, -- 'till you're done bud.
                target_logs = 32,
            }
        }
        return {tree_chop}
    end

    -- We try to get the other ores before stone since we'll end up with extra
    -- cobblestone from the digging.

    -- Go mining for ores?
    if (((not has_7_iron_ingot) and not has_raw_iron) or (not has_2_redstone) or (not has_3_diamonds)) and knows_y then
        -- We wanna mine for something.
        -- Fly down to the proper Y level if we need to.
        if wb.cur_position.position.y ~= 3 then
            return {fly_down}
        end

        -- We're at the proper Y level. Now we will deduce what ores we need and
        -- add them to the desired list. We will overshoot.

        --- @type { group: BlockGroup, desired_total: number }[]
        local groups_to_use = {}

        -- Iron
        -- Only need 7
        if not has_raw_iron then
            --- @type { group: BlockGroup, desired_total: number }
            local iron = {
                desired_total = 7,
                group = {
                    names_patterns = {
                        "iron_ore$"
                    },
                    tags = {}
                }
            }
            groups_to_use[#groups_to_use+1] = iron
        end

        -- Redstone
        -- We only need to mine a single one, as we will get 4-5.
        if not has_2_redstone then
            --- @type { group: BlockGroup, desired_total: number }
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

        -- Diamonds
        -- Two picks at a time
        if not has_3_diamonds then
            --- @type { group: BlockGroup, desired_total: number }
            local diamonds = {
                desired_total = 3,
                group = {
                    names_patterns = {
                        "diamond_ore$"
                    },
                    tags = {}
                }
            }
            groups_to_use[#groups_to_use+1] = diamonds
        end

        -- No need to include cobblestone as we should get it as an incidental.



        ---@type TaskDefinition
        local miner_task = {
            fuel_buffer = 200,
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
                    "deepslate$",
                    "amethyst",
                    "calcite",
                    "basalt",
                    "cobblestone", -- Discard last since we want this if possible.

                } },
                fuel_items = { patterns = {"coal"} },
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

        -- Once we're done mining, we should always return to the surface

        -- Go mining!
        return {miner_task, fly_up}
    end

    -- Get sand.
    -- Only do this if we already have the iron, redstone and stone to make the turtle/computer
    if (not has_sand) and (not has_glass_pane) and (not has_6_glass) and knows_y and has_2_redstone and has_7_iron_ingot and has_7_stone then
        -- Find it
        --- @type TaskDefinition
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
                        "coal", "plank", "log"
                    }
                }
            }
        }

        -- Mine it
        local mine_sand = {
            fuel_buffer = 0,
            return_to_facing = true,
            return_to_start = true,
            ---@type RecursiveMinerData
            task_data = {
                name = "recursive_miner",
                timeout = nil,
                blocks_mined_limit = 48,
                fuel_patterns = {
                    "coal", "plank", "log"
                },
                mineable_groups = {
                    {
                        names_patterns = {"sand$"},
                        tags = {},
                    }
                },
            },
        }

        -- Make sure we're high enough up first.
        if wb.cur_position.position.y < 64 then -- Below sea level
            return {fly_up, find_sand, mine_sand}
        else
            return {find_sand, mine_sand}
        end
    end

    -- We have nothing to do.
    -- This shouldn't be possible.
    -- Find another tree i guess
    return find_log

end

return deduceNextTask