--- Item related stuffs!
local item_helper = {}


--- Our internal item type.
---
--- The following information is discarded:
--- - NBT: This is just a hash of the NBT data, and is not useful to us.
--- - displayName: We don't display anything in the turtle, and the server already knows this.
--- - lore: We skip the story then complain about not knowing where to go.
--- - itemGroup: This is purely for origination in the creative menu, we do not care.
--- - durability: This is just the percentage derived from damage and maxDamage.
--- - unbreakable: No need to track this as we can just check damage
--- - enchantments: This might sound weird, but we don't care, as we can't enchant anything anyways.
--- - Potion effects: We have no use for potions.
--- - mapColor: ...what? why is this even here?
---
--- Definition based off of:
--- https://tweaked.cc/reference/item_details.html
---@class Item
---@field name string
---@field count number
---@field maxCount number|nil
---@field damage number|nil -- How many durability points have been used on this item
---@field maxDamage number|nil -- How many total durability points this item has when new.
---@field tags string[]|nil -- The tags on this item
local linter_oh_linter_lint_for_thee = {}

--- Convert the result from getItemDetail to an Item type.
---@param incoming table|nil
---@return Item|nil
function item_helper.detailsToItem(incoming)
    if not incoming then
        -- empty
        return nil
    end

    local tag_array = {}
    for tag, _ in pairs(incoming.tags) do
        tag_array[#tag_array+1] = tag
    end

    ---@type Item
    return {
        name = incoming.name,
        count = incoming.count,
        maxCount = incoming.maxCount, -- if not present, its nil.
        damage = incoming.damage,
        maxDamage = incoming.maxDamage,
        tags = tag_array
    }
end




return item_helper