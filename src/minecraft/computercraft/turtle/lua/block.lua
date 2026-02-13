--- Block related stuffs!
--- We also define all of the block types in here to keep things clean.
--- Linting is smart enough to not require re-importing of types either.
local block_helpers = {}

--- Tags that a Minecraft block can have.
--- This is NOT an exhaustive list. As almost every tag is useless to us.
---
--- It appears that tags that hold other tags are automatically determined correctly
--- when a turtle inspects, such tag collection tags(?) as #all_signs. This means
--- that we do not need to store sub-tags if we only care about a collection tag.
--- Tags returned from inspect do not include the prefix hashtag, but do contain
--- the namespace of the tag.
---
--- Annoyingly, there is no tag for falling blocks.
---
--- Data sourced from https://minecraft.wiki/w/Block_tag_%28Java_Edition%29
---
--- We do not need to transmit this data back to the control computer, as we can
--- get it again from our local minecraft data copy if needed.
---@alias MinecraftBlockTag
---| "minecraft:base_stone_overworld" -- Basic stone group, useful for mining.
---| "minecraft:features_cannot_replace" -- Holds sensible blocks that should not be broken
---| "minecraft:replaceable" -- Turtle can .place() and move into blocks with this tag. Does not drop when turtle moves into it.
---| "minecraft:dirt" -- Dirts, will change in 26.1, see wiki, but right now is a reasonable dirt check
---| "minecraft:leaves" -- Every variant of leaf block
---| "minecraft:logs" -- Every variant of log
---| "minecraft:saplings" -- Every variant of sapling
---| "minecraft:portals" -- Also includes end gateways.
---| "minecraft:sand" -- Self explanatory, contains suspicious sand
---| "minecraft:coal_ores" -- Self explanatory
---| "minecraft:iron_ores"
---| "minecraft:copper_ores"
---| "minecraft:gold_ores"
---| "minecraft:redstone_ores"
---| "minecraft:lapis_ores"
---| "minecraft:diamond_ores"
---| "minecraft:emerald_ores"


-- Probably useless but noted regardless:
-- ---| "minecraft:planks" -- This also exists, doubt it will be useful.
-- sword_efficient exists, but turtles always break in constant time anyways.
-- Also not included are all of the "mineable:tool" variants for the same reason.

-- If turtles ever have to care about tool durability and using anything besides
-- diamond pickaxes, the following tags will be important.
-- "minecraft:incorrect_for_netherite_tool" -- Empty in vanilla.
-- "minecraft:incorrect_for_diamond_tool" -- Empty in vanilla.
-- "minecraft:incorrect_for_copper_tool"
-- "minecraft:incorrect_for_gold_tool"
-- "minecraft:incorrect_for_iron_tool"
-- "minecraft:incorrect_for_stone_tool"
-- "minecraft:incorrect_for_wooden_tool"

--- Hashmap of tags that we care about
---@alias ImportantTags {MinecraftBlockTag: boolean}
---@type ImportantTags
local importantTags = {
	["minecraft:base_stone_overworld"] = true,
	["minecraft:features_cannot_replace"] = true,
	["minecraft:replaceable"] = true,
	["minecraft:dirt"] = true,
	["minecraft:leaves"] = true,
	["minecraft:logs"] = true,
	["minecraft:saplings"] = true,
	["minecraft:portals"] = true,
	["minecraft:sand"] = true,
	["minecraft:coal_ores"] = true,
	["minecraft:iron_ores"] = true,
	["minecraft:copper_ores"] = true,
	["minecraft:gold_ores"] = true,
	["minecraft:redstone_ores"] = true,
	["minecraft:lapis_ores"] = true,
	["minecraft:diamond_ores"] = true,
	["minecraft:emerald_ores"] = true,
}

--- Check if a tag is worth storing
---@param tag string
---@return boolean
function block_helpers.tagIsImportant(tag)
	return importantTags[tag] or false
end

--- Some blocks fall. There is no tag for that. Here's all of them.
---
--- Due note that this list does not include concrete powder due to its many
--- color variations. Plus, in what situation would we be dealing with
--- concrete powder??
---
--- Snow can only fall in bugrock.
---@alias BlocksThatCanFall
---| "minecraft:sand"
---| "minecraft:red_sand"
---| "minecraft:gravel"
---| "minecraft:dragon_egg" -- lol
---| "minecraft:anvil"
---| "minecraft:chipped_anvil"
---| "minecraft:damaged_anvil"
---| "minecraft:suspicious_sand"
---| "minecraft:suspicious_gravel"
---| "minecraft:pointed_dripstone" -- However, this breaks when it hits the ground. Only when pointing downwards!
---| "minecraft:scaffolding" -- Yes, but please just dont make any...

--- Hashmap of blocks that can fall
---@alias FallingBlocks {BlocksThatCanFall: boolean}
---@type FallingBlocks
fallingBlocks = {
	["minecraft:sand"] = true,
	["minecraft:red_sand"] = true,
	["minecraft:gravel"] = true,
	["minecraft:dragon_egg"] = true,
	["minecraft:anvil"] = true,
	["minecraft:chipped_anvil"] = true,
	["minecraft:damaged_anvil"] = true,
	["minecraft:suspicious_sand"] = true,
	["minecraft:suspicious_gravel"] = true,
	["minecraft:pointed_dripstone"] = true,
	["minecraft:scaffolding"] = true,
}


--- Check if a block can fall
---@param block Block
---@return boolean
function block_helpers.blockCanFall(block)
	return fallingBlocks[block.name] or false
end

--- States that a minecraft block can have.
---
--- We only care about some of these. However, we keep all of them anyways to make
--- deserialization easier. See notes below on ones you may care about on the lua
--- side.
---
--- Annoyingly, all of these inner types are strings, but we do document what
--- the underlying _intended_ type is.
---@alias MinecraftBlockState{string: string|boolean|number}

--- "age"			 number (depends on plant) -- Used to track plant growth (not saplings)
--- "eye"			 boolean -- If an end portal frame has an eye of ender.
--- "honey_level"	 number (0-5) -- How much honey is in a beehive
--- "level"			 number (depends on block) -- how full a block is of fluid, composter fullness, or light emit from a block.
--- "lit"			 boolean -- Wether the block is turned on or off, useful for furnaces.
--- "stage"			 number (0-1) -- Wether a sapling is ready to grow. Can only be 1 if growth is obstructed (?)


--- Our internal block type, used to do stuff with, well, blocks! Now including
--- position!
---
--- Field notes: (Ha!)
--- - Inspecting air ALWAYS returns `nil, "no block to inspect"`, thus
--- this is automatically converted.
--- - Name is always prefixed with their namespace, ie
--- "minecraft:grass_block", so checks based off of block names will need
--- to split on the semicolon.
--- - Inspecting always returns a table of state{[string]: any}.
--- - - There are an insane amount of bock states, hence we filter it.
--- - mapColor and mapColour contain the same value.
--- - - This is not stored. Server can reconstruct the value if needed.
--- - Tags are stored as state{[string]: boolean}.
--- - - However, we do not store most of the tags. See BlockTag.
---
--- Definition based off of:
--- https://tweaked.cc/reference/block_details.html
---@class Block
---@field pos CoordPosition
---@field state MinecraftBlockState[]
---@field tag MinecraftBlockTag[]
---@field name string
local this_is_purely_for_the_linter = {}

--- Cast a table to a Block. Requires the position of the block.
---
--- Does not clone the incoming block, do not modify it,
---
--- Clones the position, so it is safe to modify the value you provided
--- afterwards.
---
--- Takes either a table or string, since the string is the only way we
--- can detect air.
---@param incoming table|string
---@param block_position CoordPosition
---@return Block
function block_helpers.detailsToBlock(incoming, block_position)
	-- Skip all the hard stuff if this is air.
	if type(incoming) == "string" then
		return {
			pos = block_position,
			name = "minecraft:air",
			state = {},
			tag = {},
		}
	end
	---@type ImportantTags[]
	local tags = {}
	-- Keep only the tags we care about.
	-- if the incoming tags are completely empty, we need to ignore them, hence the
	-- empty table here
	for name, _ in pairs(incoming.tags or {}) do
		if block_helpers.tagIsImportant(name) then
			tags[#tags + 1] = name
		end
	end

	---@type Block
	return {
		pos = block_position,
		---@type string
		name = incoming.name,
		-- We keep all states.
		---@type MinecraftBlockState[]
		state = incoming.state,
		---@type MinecraftBlockTag[]
		tag = tags,
	}
end

return block_helpers