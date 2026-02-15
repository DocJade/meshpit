-- Walkback! see walkback.lua

local panic = require("panic")
local helpers = require("helpers")
local block_helper = require("block")
local item_helper = require("item")
local constants = require("constants")

-- ==
-- Import local constants.
-- ==


--- Integer representations of cardinal directions. 1 indexed, clockwise from north.
---@type string[]
local dirs = constants.dirs

-- Allow converting from string forms of cardinal directions to their one indexed
--- counterpart in `dirs`
---@type {[CardinalDirection]: number}
local dir_to_num = constants.dir_to_num

--- Movement vectors based on direction
---@type {[string]: CoordPosition}
local movement_vectors = constants.movement_vectors

-- ==
-- Import frequently used helper functions.
-- ==

local getTransformedPosition = helpers.getTransformedPosition
local rotateDirection = helpers.rotateDirection
local invertDirection = helpers.invertDirection
local deduceAdjacentMove = helpers.deduceAdjacentMove
local isPositionAdjacent = helpers.isPositionAdjacent
local mostSignificantDirection = helpers.mostSignificantDirection
local findFacingRotation = helpers.findFacingRotation

-- ==
-- End of importing.
-- ==

-- Table that holds the functions, and holds the state of walkback as well.
---@class WalkbackSelf
---@field cur_position MinecraftPosition
---@field walkback_chain CoordPosition[]
---@field chain_seen_positions ChainSeenPositions
local walkback = {
    -- The position we are at
    ---@type MinecraftPosition
    cur_position = {
		-- Value is uninitialized
        position = {
            x = -1000000,
            y = -1000000,
            z = -1000000,
        },
		-- Value is uninitialized
		---@diagnostic disable-next-line: assign-type-mismatch
        facing = "?"
    };

	--- The last time the turtle did some movement.
	--- This is used to throttle the speed of the turtle, since it can cause
	--- random issues if we're doing stuff too fast.
	---
	--- Tracked as milliseconds since utc epoch.
	--- @type number
	---@diagnostic disable-next-line: undefined-field
	last_movement_time = os.epoch("utc"),

	--- The speed limit of the turtle. IE, how many milliseconds have to pass
	--- between movements. Turtles seem to be able to move 2 blocks per second,
	--- but we set this a bit lower to allow some cooldown time.
	---
	--- Defined in milliseconds
	--- @type number
	speed_limit_milliseconds = 0, -- TODO: Turn this back on as needed.

    ---@type WalkbackChain
    walkback_chain = {};

    ---@type ChainSeenPositions
    chain_seen_positions = {};

	--- @type AllSeenPositions
    all_seen_positions = {};

	---@type AllSeenBlocks
	all_seen_blocks = {}

	--- In the future, it may be work storing all of the items the turtle is currently holding.
	--- This would allow fast inventory lookups to see if we have an item, but would require
	--- keeping slots up to date every time an inventory modifying action occurs.
}

-- ========================
-- Internal Walkback Methods
-- ========================

--- Record a movement based on a move direction.
--- This should be called after the move has successfully finished.
---
--- Modifies global state. (Updates our position and walkback steps)
--- @param direction MovementDirection The way in which the turtle moved.
--- @private
function walkback:recordMove(direction)
    -- If this is only a rotation, we can skip all of the costly
    -- lookups, since we do not care about facing direction.
    -- Save the previous rotation
    local original_facing = self.cur_position.facing
    -- Possibly apply the rotation
    self.cur_position.facing = rotateDirection(direction, original_facing)
    if self.cur_position.facing ~= original_facing then
        -- Only rotated. No need to record this movement.
        return
    end

    -- Movement is positional
    -- Apply the transformation,
    local new_pos = getTransformedPosition(direction, self.cur_position.facing, self.cur_position.position)
	self.cur_position.position = new_pos

	-- Trim movement if needed.
	-- If we trimmed, that means the end of the chain is already our end
	-- position and we can skip adding the new step.
	if self:trimPosition() then
		return
	end

    -- Step is not currently in the chain. Add it, and we're done!
    self:addStep()
end

--- Checks if our current position overlaps with a previous position in the
--- walkback chain, trimming out the extra moves after that point if needed.
---
--- Does not put the final position on the walkback, you are expected to
--- put it on yourself afterwards.
---
--- Takes no parameters as it operates on globals only.
---
--- Returns true if trimming occurred.
---
--- Modifies global state. (Updates walkback_chain, seen_positions)
--- @return boolean
--- @private
function walkback:trimPosition()
	-- if the end of the chain is already our current position, we can skip all of this.
	if helpers.deepEquals(self.cur_position.position, self.walkback_chain[#self.walkback_chain]) then
		return true -- we "trimmed" since we didn't move.
	end


    -- Find the position within the walkback that this position is at.
	local current_pos_key = helpers.keyFromTable(self.cur_position.position)
	if not current_pos_key then
		panic.panic("Position not key-able!")
		current_pos_key = "" -- never reached, purely for linter
	end

    local index = self.chain_seen_positions[current_pos_key]
    if index == nil then
        -- Have not seen this position before, no need for trimming.
        return false
    end
    -- We have already visited this position, we will remove all movement
    -- that occurs after it. (so we add one to skip the current position).
	-- If the index is past the end of the table,
    local slice = helpers.slice_array(self.walkback_chain, index + 1, #self.walkback_chain)
    for i, pos in ipairs(slice) do
        -- Remove from the hashset
		local key = helpers.keyFromTable(pos)
		if not key then
			panic.panic("Position not key-able!")
			key = "" -- never reached, purely for linter
		end
        self.chain_seen_positions[key] = nil
        -- Remove the position from the chain. This is safe to modify in place like this, since
        -- the deleted values will only be fully dropped once all references are dropped to it,
        -- and we are the only ones holding references to it here.
		-- This will nil out all the way to the end, thus no gaps are made.
        self.walkback_chain[index + i] = nil
		-- We do not trim the all list.
    end

	-- All done, we don't add the current position ourselves here.
	return true
end

--- Adds a step to the walkback chain.
---
--- Will throw if the position has already been seen.
---
--- Takes no parameters as it operates on globals only.
---
--- Modifies global state. (Updates walkback_chain, seen_positions)
--- @private
function walkback:addStep()
    -- Make sure we haven't already seen this position
	local current_pos_key = helpers.keyFromTable(self.cur_position.position)
	if not current_pos_key then
		panic.panic("Position not key-able!")
		current_pos_key = "" -- never reached, purely for linter
	end

    if self.chain_seen_positions[current_pos_key] ~= nil then
        panic.panic("Tried to add a position to the walkback_chain that we've already seen!")
    end
    -- Add position to the end of the chain
	-- Make a copy so we don't have all of the keys just referencing the current position.
	local pos_copy = helpers.deepCopy(self.cur_position.position)
    self.walkback_chain[#self.walkback_chain + 1] = pos_copy

    -- Add it to the hashset as an index into the chain.
    self.chain_seen_positions[current_pos_key] = #self.walkback_chain

	-- Add it to the all seen positions hashset.
	-- This is fine if it overwrites an already seen value, since that has no effect.
	self.all_seen_positions[current_pos_key] = true
end

--- Perform a turtle movement based off of a MovementDirection.
--- @param movement MovementDirection
--- @return boolean, MovementError|nil
--- @private
function walkback:doMovement(movement)
	-- We throttle movement speed to
	-- No match statements yay.
	-- Ordered on what i presume to be the most common movement cases.
	local result
	local reason
	if movement == "f" then
		result, reason = self:forward()
	elseif movement == "u" then
		result, reason = self:up()
	elseif movement == "d" then
		result, reason = self:down()
	elseif movement == "b" then
		result, reason = self:back()
	elseif movement == "r" then -- right is preferred.
		result, reason = self:turnRight()
	elseif movement == "l" then
		result, reason = self:turnLeft()
	end
	return result, reason
end

--- Get the position of the block to a side of the turtle relative to the
--- turtle's current facing direction. Re-purposes the MovementDirection type,
--- however left and right are now literally the left and right side of the
--- turtle from the turtle's front perspective.
---
--- Does not modify global state.
---@param direction MovementDirection re-defines left and right.
---@returns CoordPosition
function walkback:getAdjacentBlock(direction)
	local pos = self.cur_position.position
	local facing = self.cur_position.facing
	local delta

	if direction == "u" or direction == "d" then
		-- Up and down are constant
		delta = movement_vectors[direction]
	elseif direction == "f" then
		-- Forward is our current facing direction's vector
		delta = movement_vectors[facing]
	elseif direction == "b" then
		-- Flip that around
		local f = invertDirection(facing)
		delta = movement_vectors[f]
	else
		-- is either left or right, thus we can rotate to that side and
		-- then use a movement vector from that, since we would now be facing that side.
		local side_facing = rotateDirection(direction, facing)
		delta = movement_vectors[side_facing]
	end

	return {
		x = pos.x + delta.x,
		y = pos.y + delta.y,
		z= pos.z + delta.z,
	}
end


--- Document a block that we have seen and store it in self.all_seen_blocks.
--- Will overwrite whatever block has already been seen in that position. Use this
--- method when destroying blocks (setting them to air), when placing blocks, or
--- when scanning surroundings.
---
--- Does not clone the block. Thus callers MUST NOT modify it after storing.
---
--- Modifies global state. (Updates all_seen_blocks)
---@param position CoordPosition
---@param block Block
--- @private
function walkback:saveBlock(position, block)
	-- We can assert this returned key is not nil, since coordinate positions
	-- are only numbers.
	local key = helpers.keyFromTable(position)
	---@cast key string
	self.all_seen_blocks[key] = block
end

-- ========================
-- Methods
-- ========================

-- ============
-- New methods
-- ============

-- ======
-- Initialization
-- ======

--- Sets up walkback for the first time. Should only be called once!
--- @param x number X position
--- @param y number Y position
--- @param z number Z position
--- @param facing CardinalDirection Facing direction
--- @return nil
function walkback:setup(x, y, z, facing)
    self.cur_position.position.x = x
    self.cur_position.position.y = y
    self.cur_position.position.z = z
    self.cur_position.facing = facing
	-- Add the first step, which our current position.
	self:addStep()
end

-- ======
-- Rewind related
-- ======

--- Set the new start of the walkback chain.
---
--- This will fail if the chain has any content, thus if you want to
--- completely discard the current chain, you must `.pop()` it off first, or
--- completely reset walkback state with `.hard_reset()`
---
--- Returns true if current position was marked as the new start, or
--- false if a walkback chain already exists.
---
--- Takes no parameters as it operates on globals only.
---
--- Modifies global state. (Updates walkback_chain, seen_positions)
---@return boolean
function walkback:mark()
    -- Cancel if we have any internal state.
    if next(self.walkback_chain) ~= nil and next(self.chain_seen_positions) ~= nil then
        return false
    end
    -- Reset!
    local x = self.cur_position.position.x
    local y = self.cur_position.position.y
    local z = self.cur_position.position.z
    local facing = self.cur_position.facing
    self:setup(x, y, z, facing)
    return true
end

--- Rewind the turtle to the marked position.
--- You should ensure you have enough fuel for the full walkback first.
---
--- Returns a bool, string|nil pair denoting success or a failure reason.
---
--- Will return `"Not enough fuel"` if the rewind could never possibly work due
--- to being too long.
---@return boolean, MovementError|"not enough fuel"|"nothing to walkback"|nil
function walkback:rewind()
	-- If there is nothing to rewind, return false.
	if self:previousPosition() == nil then
		return false,"nothing to walkback"
	end
    -- Composed of other methods for implementation simplicity! :D
    -- Pre-check if we have enough fuel. If we don't, then we won't
    -- even start.
    local fuel_level = self:getFuelLevel()
	local cost = self:cost()
	if cost > fuel_level then
		return false, "not enough fuel"
	end
	-- Run walkback steps until we run out of steps.
	while type(self:previousPosition()) ~= "nil" do
		local ok, result = self:stepBack()
		if not ok then
			return false, result
		end
	end

	-- All done!
	return true, nil
end

--- Go back to the previous position in the current rewind.
---
--- Returns a bool, string|nil pair denoting success or a failure reason.
---
--- Failure reasons:
--- "fuel" - No fuel, cannot move.
--- "obstacle" - Could not complete walkback due to a block being in the way.
---@return boolean, MovementError|nil
function walkback:stepBack()
	-- The previous position should always be adjacent, we're just gonna assume
	-- that entirely here for speed. Good luck!
	local dest = panic.unwrap(self:previousPosition())
	-- There should be at least one move.
	local start = self.cur_position
	local moves = panic.unwrap(deduceAdjacentMove(start, dest))
	for _, move in ipairs(moves) do
		local ok, result = self:doMovement(move)
		if not ok then
			return ok, result
		end
	end
	return true, nil
end

--- Get a REFERENCE to the previous position.
--- == !!DO NOT MODIFY THE RETURNED VALUE WITHOUT CLONING!! ==
---
--- Returns `nil` if there is no previous position.
---@return CoordPosition|nil
function walkback:previousPosition()
    return self.walkback_chain[#self.walkback_chain - 1]
end

--- How much fuel it would cost to run the full rewind
--- from the current position.
---
---@return number
function walkback:cost()
	-- The fuel cost is the same as the number of moves to make, minus 1 for
	-- the current position.
	return #self.walkback_chain - 1
end

--- Pop off the entire current walkback state.
--- This can be used to store walkbacks for later, but care must be taken to
--- return to the original starting position before pushing the walkback state back.
---
--- The original starting position is contained within `position`, do NOT modify it.
---
--- Do note that this will also clear what positions we've seen.
---
--- Returns nil if there is no current chain.
---@return nil|PoppedWalkback
function walkback:pop()
	-- Cancel if there is currently no chain.
	if self:previousPosition() == nil then
		return nil
	end

	local position_copy = helpers.deepCopy(self.cur_position)
	local chain_copy = helpers.deepCopy(self.walkback_chain)
	local seen_copy = helpers.deepCopy(self.chain_seen_positions)
	---@type PoppedWalkback
	local copy = {
		position = position_copy,
		chain = chain_copy,
		seen = seen_copy
	}
	-- Remove the old walkback
	-- We do not modify the current position
	self.walkback_chain = {}
	self.chain_seen_positions = {}
	return copy
end

--- Sets the current walkback state based off of a previously popped state.
---
--- Current walkback must be finished, and the walkback being pushed must have
--- an identical starting position, including the facing direction.
---
--- "Consumes" the incoming walkback, please do not modify it after pushing.
---
--- Returns a boolean on wether or not the walkback could be loaded.
---@param state PoppedWalkback
---@return boolean
function walkback:push(state)
	-- Do we have any current steps?
	if self:previousPosition() ~= nil then
		return false
	end
	-- Are we in the right position?
	if not helpers.deepEquals(self.cur_position, state.position) then
		return false
	end

	-- Push that on!
	self.walkback_chain = state.chain
	self.chain_seen_positions = state.seen
	return true
end

--- Check if we have previously visited a position.
---
--- Takes in a string key generated from a CoordPosition.
---
--- This does not check if the key position is valid, or even if the key is in
--- the correct format for the hashmaps.
---
--- If all is set, this will include positions that are not necessarily in the
--- current walkback chain.
---@param position string Created with helpers.keyFromTable(CoordPosition)
---@param full boolean? Defaults to false.
---@return boolean
function walkback:posQuery(position, full)
	local check_full = full or false
	if check_full then
		-- We don't need to check the current walkback, as this
		-- also contains it.
		return self.all_seen_positions[position] ~= nil
	end
	-- current walkback
	return self.chain_seen_positions[position] ~= nil
end

--- COMPLETELY resets the state of walkback, including ALL data such as
--- previously seen blocks. Only do this AFTER uploading information to the
--- control computer, as we really really want that block data, otherwise we
--- wasted a whole bunch of time and memory.
function walkback:hardReset()
	self.all_seen_positions = {}
	self.chain_seen_positions = {}
	self.walkback_chain = {}
	-- Doesn't remove the current position for hopefully obvious reasons.
end

--- Returns the full walkback state of this turtle as a table of all of
--- the data contained within the global `walkback` variable.
---
--- This will not change the global state, this operation is read-only.
---
--- !!!!! This does not contain the inventory of the turtle !!!!!
---
--- This may be EXTREMELY slow. Only run when absolutely needed.
---
--- Do note that the keys may be in a different order, but arrays will remain
--- in the correct order.
---
--- Returns a table. Will be serialized on the way out.
---@return table -- See function definition for format.
function walkback:dataJson()
	-- If we serialize this directly, we would end up also passing
	-- all of the functions, which we do not care about. So we must extract
	-- what we do care about by reference.
	local needed = {
		cur_position = self.cur_position,
		all_seen_positions = self.all_seen_positions,
		all_seen_blocks = self.all_seen_blocks,
		chain_seen_positions = self.chain_seen_positions,
		walkback_chain = self.walkback_chain,
	}
	return needed
end

--- Returns all of the items the turtle currently has in its inventory as an array.
--- Empty slots are null.
---
--- Returns a table in the inventory format. Must be serialized later.
---@return table
function walkback:inventoryJSON()
	--- array of optionals, dont know how to lint that
	local slots = {}
	---@diagnostic disable-next-line: undefined-global
	local json_null = textutils.json_null
	for i= 1, 16 do
		local found = self:getItemDetail(i, true)
		-- Fix empty slots
		---@diagnostic disable-next-line: undefined-global
		if found ~= nil then
			local array_value = {
				["item"] = found.name,
				["count"] = found.count
			}
			slots[#slots+1] = array_value
		end
		-- No item
		slots[#slots+1] = json_null
	end
	local inv = {
		["size"] = 16,
		["slots"] = slots
	}

	return inv
end



-- ======
-- Block data related
-- ======

--- Checks if a block has been seen at a position. Returns the `Block` at that
--- position if one has been seen.
---
--- Returns a block, unless:
--- - We have not documented this position.
--- - The block was air, and `and_air` was not set.
--- - - You can only get information about air blocks with `and_air` set and this
--- - - is by design, since we want a fast check on wether or not a block is solid,
--- - - we usually do not care if it is air.
---
--- Returns `nil` if a block has not been logged at that position. Or, if `and_air`
--- is set to false, if we have logged an air block, we will still return nil.
---@param position CoordPosition
---@param and_air boolean? Enables returning air blocks.
---@return Block|nil
function walkback:blockQuery(position, and_air)
	---@type Block|nil
	local found = self.all_seen_blocks[helpers.keyFromTable(position)]
	if found ~= nil and (found.name ~= "minecraft:air" or and_air) then
		---@type Block
		return found
	end
end

-- ============
-- Movement functions
-- ============
-- These are not scanning movements, they are meant to be fast.
-- Call these whenever you know exactly where you are going.
-- But remember, the more we scan, the more we learn!


--- Helper function to yield until we are allowed to move.
---
--- This enforces the speed limit on turtles.
local function waitTillCanMove()

	-- TODO:
	-- TODO:
	-- TODO:
	-- TODO: This absolutely SPAMS events, this should call the MeshOS level
	-- TODO: sleep if it exists, or do a timer-based sleep itself manually.
	-- TODO:
	-- TODO: Additionally, these same speed limits should be applied to mining
	-- TODO: and placing blocks.
	-- TODO:
	-- TODO:
	-- TODO:

	local when_can_move = walkback.last_movement_time + walkback.speed_limit_milliseconds
	local quick_yield = helpers.quick_yield
	---@diagnostic disable-next-line: undefined-field
	while when_can_move > os.epoch("utc") do
		quick_yield()
	end
	-- We moved!
	---@diagnostic disable-next-line: undefined-field
	walkback.last_movement_time = os.epoch("utc")
end

--- Move the turtle forwards.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:forward()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.forward()
	if a then
		self:recordMove("f")
	end
	waitTillCanMove()
	return a, b
end

--- Move the turtle backwards. (NOT going back a step in the walkback chain)
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:back()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.back()
	if a then
		self:recordMove("b")
	end
	waitTillCanMove()
	return a, b
end

--- Move the turtle upwards.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:up()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.up()
	if a then
		self:recordMove("u")
	end
	waitTillCanMove()
	return a, b
end

--- Move the turtle downwards.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:down()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.down()
	if a then
		self:recordMove("d")
	end
	waitTillCanMove()
	return a, b
end

-- Turning CANNOT fail due to how it is implemented internally.
-- turtle/core/TurtleTurnCommand.java
-- We cannot call the underlying command directly, so we can never get the
-- string error, and the LEFT and RIGHT cases ALWAYS return true.

--- Turns the turtle to the left.
---
--- This operation cannot fail, but has the same return format as the other
--- movement actions for ease of use.
---@return true, nil
function walkback:turnLeft()
	---@diagnostic disable-next-line: undefined-global
	turtle.turnLeft()
	self:recordMove("l")
	waitTillCanMove()
	return true, nil
end

--- Turns the turtle to the right.
---
--- This operation cannot fail, but has the same return format as the other
--- movement actions for ease of use.
---@return true, nil
function walkback:turnRight()
	---@diagnostic disable-next-line: undefined-global
	turtle.turnRight()
	self:recordMove("r")
	waitTillCanMove()
	return true, nil
end

-- ======
-- New methods
-- ======

--- Turn to face an adjacent block. Does nothing if already facing the block, or
--- if the block is adjacent vertically or horizontally.
---
--- Returns false if the requested block was not next to the turtle.
--- @param adjacent CoordPosition
--- @return boolean
function walkback:faceAdjacentBlock(adjacent)
	-- Check that the position is indeed, adjacent.
	if not isPositionAdjacent(self.cur_position.position, adjacent) then
		return false
	end

	-- Skip if the block is above or below
	if self.cur_position.position.y ~= adjacent.y then
		-- Vertical move
		return false
	end

	-- Since we know the block is one block away from us, and is in line with
	-- us, the most significant direction is whatever cardinal position we need
	-- to face to be looking at the block.

	-- We need a delta to calculate that.
	---@type CoordPosition
	local delta = {
		x = adjacent.x - self.cur_position.position.x,
		y = adjacent.y - self.cur_position.position.y, -- yes this is never read.
		z = adjacent.z - self.cur_position.position.z,
	}

	-- Cast that to a direction
	local direction = mostSignificantDirection(delta.x, delta.z)

	-- Now rotate to face that position!
	self:turnToFace(direction)

	-- All done!
	return true
end

--- Move into an adjacent block.
---
--- May rotate turtle.
---
--- Has the same return format as `self:forward()
---
--- Returns false, nil if the requested block was not next to the turtle.
--- @param adjacent CoordPosition
---@return boolean, MovementError|nil
function walkback:moveAdjacent(adjacent)
	-- Check that the position is indeed, adjacent.
	if not isPositionAdjacent(self.cur_position.position, adjacent) then
		return false
	end

	-- Use our inner adjacent move call
	local start = self.cur_position
	local moves = deduceAdjacentMove(start, adjacent)

	-- This is not nil, since we know its not our current position.
	---@cast moves MovementDirection[]

	for _, move in ipairs(moves) do
		local ok, result = self:doMovement(move)
		if not ok then
			-- Same kind of return structure as normal movement.
			return ok, result
		end
	end

	return true, nil
end

-- These scan post-movement.

--- Move the turtle forwards.
---
--- Additionally scans the blocks around the turtle post-movement.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:forwardScan()
	local a, b = self:forward()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	-- Scan time
	self:turnLeft()
	self:inspect()

	self:turnRight()
	self:inspect()
	self:turnRight()
	self:inspect()

	self:turnLeft()

	self:inspectUp()
	self:inspectDown()

	return a, b
end

--- Move the turtle backwards. (NOT going back a step in the walkback chain)
---
--- Additionally scans the blocks around the turtle post-movement.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:backScan()
	-- Fairly niche movement, mostly for rewinding.
	-- To scan behind us we need to make a full rotation anyways, so
	-- we can just use the full spin scan.
	local a, b = self:back()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	self:spinScan()
	return a, b
end

--- Move the turtle upwards.
---
--- Additionally scans the blocks around the turtle post-movement.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:upScan()
	-- The blocks on every side of use are different now, spin
	local a, b = self:up()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	self:spinScan()
	return a, b
end

--- Move the turtle downwards.
---
--- Additionally scans the blocks around the turtle post-movement.
---
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback:downScan()
	-- The blocks on every side of use are different now, spin
	local a, b = self:down()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	self:spinScan()
	return a, b
end

--- Spins the turtle around and documents every block around it.
--- Finishes in the same position and facing direction the turtle started in.
---@return nil
function walkback:spinScan()
	-- We'll get the front on the final turn
	self:turnRight() -- We prefer clockwise turns.
	self:inspect() -- Save the block data internally.
	self:turnRight()
	self:inspect()
	self:turnRight()
	self:inspect()
	self:turnRight()
	self:inspect()
	self:inspectUp()
	self:inspectDown()
end

--- Turns to face a cardinal direction.
---
--- Also scans while turning.
---@param direction CardinalDirection
function walkback:turnToFace(direction)
	-- Rotate if needed
	local start_facing = self.cur_position.facing
	local end_facing = direction

	-- Skip if we don't need to do anything
	if start_facing == end_facing then return end

	local rotations = findFacingRotation(start_facing, end_facing) or {}
	for _, move in ipairs(rotations) do
		-- Rotations cannot fail.
		self:doMovement(move)
		-- Might as well inspect the blocks around us when we do this.
		self:inspect()
	end

	self:inspectUp()
	self:inspectDown()
end

-- ============
-- Inventory functions
-- ============

--- Insert the currently selected slot of items into the inventory in front of
--- the turtle, or drop the items in the world if there was no inventory.
---
--- Takes in a limit of how many items to move, defaults to the entire contents
--- of the slot.
---
--- Do not attempt to drop with a limit of zero, or drop from a slot with no
--- items in it. That wouldn't do anything anyways.
---
--- Returns false if there was not enough room in the destination container.
---@param limit number
function walkback:drop(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = self:getItemCount(self:getSelectedSlot())
	assert(actual > 0, "Tried to drop from an empty slot!")
	-- This only returns "No space for items" or "No items to drop".
	-- Since we already know some amount of items is being dropped, the only
	-- failure mode is running out of space.
	---@diagnostic disable-next-line: undefined-global
	local a, _ = turtle.drop(limit)
	return a
end

--- Insert the currently selected slot of items into the inventory above
--- the turtle, or drop the items in the world if there was no inventory.
---
--- Takes in a limit of how many items to move, defaults to the entire contents
--- of the slot.
---
--- Do not attempt to drop with a limit of zero, or drop from a slot with no
--- items in it. That wouldn't do anything anyways.
---
--- Returns false if there was not enough room in the destination container.
function walkback:dropUp(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = self:getItemCount(self:getSelectedSlot())
	assert(actual > 0, "Tried to drop from an empty slot!")
	-- This only returns "No space for items" or "No items to drop".
	-- Since we already know some amount of items is being dropped, the only
	-- failure mode is running out of space.
	---@diagnostic disable-next-line: undefined-global
	local a, _ = turtle.dropUp(limit)
	return a
end

--- Insert the currently selected slot of items into the inventory below
--- the turtle, or drop the items in the world if there was no inventory.
---
--- Takes in a limit of how many items to move, defaults to the entire contents
--- of the slot.
---
--- Do not attempt to drop with a limit of zero, or drop from a slot with no
--- items in it. That wouldn't do anything anyways.
---
--- Returns false if there was not enough room in the destination container.
function walkback:dropDown(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = self:getItemCount(self:getSelectedSlot())
	assert(actual > 0, "Tried to drop from an empty slot!")
	-- This only returns "No space for items" or "No items to drop".
	-- Since we already know some amount of items is being dropped, the only
	-- failure mode is running out of space.
	---@diagnostic disable-next-line: undefined-global
	local a, _ = turtle.dropDown(limit)
	return a
end

--- Changes the currently selected slot.
---
--- Doesn't return anything, since this always works assuming you are not out
--- of range.
---
--- Accepted values are 1-16.
---@param slot number
function walkback:select(slot)
	panic.assert( slot > 0 and slot <= 16, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	---@diagnostic disable-next-line: undefined-global
	turtle.select(slot)
end

--- Get the number of items in a slot. Defaults to the currently selected slot.
---
--- This is extremely cheap, this can be called millions of times per second.
---
--- The difference in CPU time between this and getItemDetail() without detailed
--- info is insignificant. So if you are going to manipulate this item further,
--- consider loading the slot's item directly.
---@param slot number
---@return number
function walkback:getItemCount(slot)
	panic.assert(slot > 0 and slot <= 16, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.getItemCount(slot)
end

--- Get how many more items of the same type can be stored in a slot. Defaults
--- to the currently selected slot.
---
--- IE if a slot has 13 dirt in it, this will return 51.
---
--- This is extremely cheap, this can be called millions of times per second.
---
--- Returns 64 for empty slots.
---@param slot number
---@return number
function walkback:getItemSpace(slot)
	panic.assert(slot > 0 and slot <= 16, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.getItemSpace(slot)
end

--- Suck an item from the inventory in front of the turtle,
--- or from an item floating in the world.
---
--- Sucking 0 items does nothing except yield, and returns true.
---
--- Takes in a number of items to suck up up to 64. Defaults to a stack.
---
--- Puts the sucked item in the first free slot,
--- starting from the currently selected slot.
---
--- Returns true if items were picked up, or a reason that not items were sucked.
---@param count number
---@return boolean, ItemError|nil
function walkback:suck(count)
	count = count or 64
	panic.assert(count <= 64 and count >= 0, "Invalid suck amount! [" .. count .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.suck()
end

--- See suck(), but up!
---@param count number
---@return boolean, ItemError|nil
function walkback:suckUp(count)
	count = count or 64
	panic.assert(count <= 64 and count >= 0, "Invalid suck amount! [" .. count .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.suckUp()
end

--- See suck(), but down!
---@param count number
---@return boolean, ItemError|nil
function walkback:suckDown(count)
	count = count or 64
	panic.assert(count <= 64 and count >= 0, "Invalid suck amount! [" .. count .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.suckDown()
end

--- Move an item from the selected slot to another slot. Takes in a limit of
--- how many items to move. Defaults to 64.
---
--- Do not attempt to move 0 items. Nothing would happen anyways.
---
--- Will move as many items as possible, into the new slot, leaving the remainder
--- behind in the selected slot.
--- Returns false if not all of the items could be moved into the slot.
---@param slot number
---@param count number|nil
---@return boolean
function walkback:transferTo(slot, count)
	panic.assert(slot >= 1 and slot <= 17, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	panic.assert(65 >= count or 0 <= count, "Invalid transfer amount! [" .. count .. "]")
	-- I'm pretty sure its set to 64 by default? If i'm reading the java source right.
	-- Experimenting with it in-game seems to imply it doesn't really matter anyways,
	-- since it will just move the maximum amount possible if no argument is passed.
	-- Also, the only time it returns false is when there is `"No space for items"`,
	-- so there is no need for a string return. The CC:T docs say this will throw,
	-- but it does not. So this is safe.
	---@diagnostic disable-next-line: undefined-global
	local a, _ = turtle.transferTo(slot, count)
	return a
end

--- Check if the item in the currently selected slot is the same as another
--- provided slot. Only checks the name of the item.
---@param slot number
---@return boolean
function walkback:compareTo(slot)
	panic.assert(16 >= slot and slot >= 1, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	-- Already bounds checked, this will not throw
	---@diagnostic disable-next-line: undefined-global
	return turtle.compareTo(slot)
end

--- Returns what slot is currently selected.
---
--- Returns a number between 1 and 16 inclusive.
---@return number
function walkback:getSelectedSlot()
	---@diagnostic disable-next-line: undefined-global
	return turtle.getSelectedSlot()
end

--- Get information about the items in the given slot. Slot defaults to the
--- currently selected slot.
---
--- Getting non-detailed information is extremely cheap, basic benchmarks show
--- this can be called over a million times per second.
---
--- Detailed returns more data, but see the note below.
---
--- Returns `nil` if there is no item in this slot.
---
--- Getting details about an item with `detailed` set is significantly slower, and
--- requires running on minecraft's _SERVER_ thread, which means it will block
--- other computers completely until the item lookup is done, so you should
--- only get more details when absolutely necessary!
---
--- https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/common/src/main/java/dan200/computercraft/impl/detail/DetailRegistryImpl.java#L32-L49
---@param slot number|nil
---@param detailed boolean|nil
---@return Item|nil
function walkback:getItemDetail(slot, detailed)
	---@diagnostic disable-next-line: undefined-global
	return item_helper.detailsToItem(turtle.getItemDetail(slot, detailed))
end

-- ======
-- New methods
-- ======

--- Transfer items between two arbitrary slots. Has the same failure modes and
--- working method of transferTo().
---@param source_slot number
---@param destination_slot number
---@param count number|nil
---@return boolean
function walkback:transferFromSlotTo(source_slot, destination_slot, count)
	-- Nothing to do if both slots are the same slot.
	if source_slot == destination_slot then
		return true
	end

	-- Remember the old slot
	local old = self:getSelectedSlot()

	-- Do the move.
	self:select(source_slot)
	local result = self:transferTo(destination_slot, count)

	-- go back
	self:select(source_slot)
	self:select(old)
	return result
end

--- Checks if two arbitrary slots have the same item (by name).
---@param slot_a number
---@param slot_b number
---@return boolean
function walkback:compareTwoSlots(slot_a, slot_b)
	-- Nothing to do if both slots are the same slot.
	if slot_a == slot_b then
		return true
	end

	-- Slot assertions happen in sub-calls
	-- Save the active slot
	local old = self:getSelectedSlot()
	-- Do the comparison
	self:select(slot_a)
	local result = self:compareTo(slot_b)
	-- go back
	self:select(old)
	return result
end

--- Count how many slots in the turtle's inventory are empty.
---
--- This is an alias of pre-existing methods, but provided as a convenience.
--- @return number
function walkback:countEmptySlots()
	local total = 0
	for i = 1, 16 do
		if self:getItemCount(i) == 0 then
			total = total + 1
		end
	end
	return total
end

--- Find an empty slot in the inventory, if one exists.
--- @return number|nil
function walkback:FindEmptySlot()
	for i = 1, 16 do
		if self:getItemCount(i) == 0 then
			return i
		end
	end
	-- No empty slot
	return nil
end

--- Checks if there are any empty slots in the inventory.
---
--- This is an alias of pre-existing methods, but provided as a convenience.
--- @return boolean
function walkback:haveEmptySlot()
	return self:FindEmptySlot() ~= nil
end

--- Count how many item's names in the inventory match a pattern.
---
--- IE, `log` would match `minecraft:oak_log` as well as `minecraft:spruce_log`
--- @param pattern string
--- @return number
function walkback:inventoryCountPattern(pattern)
	local matches = 0
	for i = 1, 16 do
		-- Get item, if any
		local item = self:getItemDetail(i)
		if not item then goto continue end

		-- Check if pattern matches
		if not helpers.findString(item.name, pattern) then goto continue end

		-- Match! Add to tally.
		matches = matches + item.count
		::continue::
	end
	return matches
end

--- Count how many items in the inventory have a specified tag.
--- @param item_tag string
--- @return number
function walkback:inventoryCountTag(item_tag)
	local matches = 0
	for i = 1, 16 do
		-- Get item, if any
		local item = self:getItemDetail(i)
		if not item then goto continue end

		-- Check if the tag is in there
		for _, tag in ipairs(item.tags) do
			-- return if it matches
			if tag == item_tag then
				matches = matches + item.count
				break
			end
		end

		::continue::
	end
	return matches
end

--- Find the first slot in the turtle's inventory that matches a pattern, if any.
---
--- Search direction can be picked. Defaults to searching from the first to last
--- slot.
---
--- Returns the slot number, or `nil` if no slot with a matching item is found.
--- @param pattern string
--- @param search_downwards boolean?
--- @return number|nil
function walkback:inventoryFindPattern(pattern, search_downwards)
	local swap = search_downwards or false
	local loop_start = 1
	local loop_end = 16
	local loop_change = 1
	-- swap search direction if needed.
	if swap then
		loop_start, loop_end = loop_end, loop_start
		loop_change = -1
	end
	for i = loop_start, loop_end, loop_change do
		-- Get item, if any
		local item = self:getItemDetail(i)
		if not item then goto continue end

		-- Check if pattern matches
		if helpers.findString(item.name, pattern) then
			-- Match! return that!
			return i
		end

		::continue::
	end
	-- No match.
	return nil
end

--- Find the first slot in the turtle's inventory where the item has a given
--- tag, if any.
---
--- Search direction can be picked. Defaults to searching from the first to last
--- slot.
---
--- Returns the slot number, or `nil` if no slot with a matching item is found.
--- @param item_tag string
--- @param search_downwards boolean?
--- @return number|nil
function walkback:inventoryFindTag(item_tag, search_downwards)
	local swap = search_downwards or false
	local loop_start = 1
	local loop_end = 16
	local loop_change = 1
	-- swap search direction if needed.
	if swap then
		loop_start, loop_end = loop_end, loop_start
		loop_change = -1
	end
	for i = loop_start, loop_end, loop_change do
		-- Get item, if any
		local item = self:getItemDetail(i)
		if not item then goto continue end

		-- Check if the tag is in there
		for _, tag in ipairs(item.tags) do
			-- return if it matches
			if tag == item_tag then return i end
		end

		::continue::
	end
	-- No match.
	return nil
end

--- Swaps the contents of two inventory slots.
---
--- If both slots are full, this will require a third, empty slot to do the swap.
---
--- Returns false if a third empty slot was needed, but couldn't be found.
---@param slot_1 number
---@param slot_2 number
---@return boolean
function walkback:swapSlots(slot_1, slot_2)
	-- Assert that both incoming slots actually have some items
	local one_count = self:getItemCount(slot_1)
	local two_count = self:getItemCount(slot_2)

	-- nothing to do if both are empty
	if one_count == 0 and two_count == 0 then
		return true
	end

	-- As a good gesture, if one of the two slots is empty, we'll still do the
	-- swap.
	if one_count == 0 or two_count == 0 then
		-- The empty one is the destination slot.
		if two_count > one_count then
			slot_1, slot_2 = slot_2, slot_1
		end
		-- This cannot fail as one is empty.
		self:transferFromSlotTo(slot_1, slot_2)
		return true
	end

	-- Both slots have items.

	-- Make sure there is room.
	local temp_slot = self:FindEmptySlot()
	if not temp_slot then
		-- No third slot
		return false
	end

	-- Do the swap
	-- These should not fail, as we asserted the third slot is empty.
	self:transferFromSlotTo(slot_1, temp_slot)
	self:transferFromSlotTo(slot_2, slot_1)
	self:transferFromSlotTo(temp_slot, slot_1)
	return true
end


-- ============
-- Environment detection
-- ============
-- Actually silently calls `inspect` and only returns the bool, so we can
-- still log the underlying block.

--- Check if there is a solid block in front of the turtle. Solid refers to
--- any block that we cannot move into. Unlike the base CC:Tweaked methods, this
--- will return false on fluids, as we can move through those.
---@return boolean
function walkback:detect()
	return self:inspect() ~= nil
end

--- Check if there is a solid block in front of the turtle. Solid refers to
--- any block that we cannot move into. Unlike the base CC:Tweaked methods, this
--- will return false on fluids, as we can move through those.
---@return boolean
function walkback:detectUp()
	return self:inspectUp() ~= nil
end

--- Check if there is a solid block in front of the turtle. Solid refers to
--- any block that we cannot move into. Unlike the base CC:Tweaked methods, this
--- will return false on fluids, as we can move through those.
---@return boolean
function walkback:detectDown()
	return self:inspectDown() ~= nil
end

-- ======
-- New methods
-- ======

--- Check if a block at a position is solid.
---
--- Returns `nil` if we have not seen that block.
---@param pos CoordPosition
---@return boolean|nil
function walkback:detectAt(pos)
	return self:blockQuery(pos) ~= nil
end

-- ============
-- Block comparison
-- ============

--- Check if the block in front of the turtle is the same as the item in the
--- currently held slot.
---
--- Always returns false if the slot is empty, or if there is no block in the specified
--- direction.
---@return boolean
function walkback:compare()
	-- We don't use the version built into computercraft as it does RNG rolls
	-- with block loot-tables and thats stupid.
	-- We assume item names == block names
	local block = self:inspect()
	local item = self:getItemDetail()
	if (not block) or (not item) then
		-- missing one of the things to compare
		return false
	end
	return block.name == item.name
end

--- Check if the block above the turtle is the same as the item in the
--- currently held slot.
---
--- Always returns false if the slot is empty, or if there is no block in the specified
--- direction.
---@return boolean
function walkback:compareUp()
	local block = self:inspectUp()
	local item = self:getItemDetail()
	if (not block) or (not item) then
		return false
	end
	return block.name == item.name
end

--- Check if the block below the turtle is the same as the item in the
--- currently held slot.
---
--- Always returns false if the slot is empty, or if there is no block in the specified
--- direction.
---@return boolean
function walkback:compareDown()
	local block = self:inspectDown()
	local item = self:getItemDetail()
	if (not block) or (not item) then
		return false
	end
	return block.name == item.name
end

-- ======
-- New methods
-- ======

--- Check if the block at some position is the same as the item in the
--- currently held slot.
---
--- Always returns false if the slot is empty, or if there is no block in the specified
--- direction.
---
--- Returns `nil` if we do not know what block is at that position.
---@param pos CoordPosition
---@return boolean|nil
function walkback:compareAt(pos)
	local contained, block = self:inspectAt(pos)
	if (not contained) or (block == nil) then
		return false
	end
	local item = self:getItemDetail()
	if (not block) or (not item) then
		return false
	end
	return block.name == item.name
end


-- ============
-- Block inspection
-- ============
-- these should update our internal state.
-- The only case where inspection fails, it returns `"No block to inspect"`, which
-- means the block was air. We can exploit this fact, and we do in block.lua

--- Get information about the block in front of the turtle.
---
--- Returns `nil` if the block in front of the turtle is air.
---@return Block|nil
function walkback:inspect()
	local pos = self:getAdjacentBlock("f")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspect()
	local block = block_helper.detailsToBlock(b, pos)
	self:saveBlock(pos, block)
	if block.name ~= "minecraft:air" then
		return block
	end
end

--- Get information about the block above the turtle.
---
--- Returns `nil` if the block in front of the turtle is air.
---@return Block|nil
function walkback:inspectUp()
	local pos = self:getAdjacentBlock("u")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspectUp()
	local block = block_helper.detailsToBlock(b, pos)
	self:saveBlock(pos, block)
	if block.name ~= "minecraft:air" then
		return block
	end
end

--- Get information about the block below the turtle.
---
--- Returns `nil` if the block in front of the turtle is air.
---@return Block|nil
function walkback:inspectDown()
	local pos = self:getAdjacentBlock("d")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspectDown()
	local block = block_helper.detailsToBlock(b, pos)
	self:saveBlock(pos, block)
	if block.name ~= "minecraft:air" then
		return block
	end
end

-- ======
-- New methods
-- ======

--- Get information about the block at an arbitrary position.
---
--- Returns a boolean, block|nil pair, with the boolean signalling that the
--- block was indeed in the hashmap.
---
--- Returns `nil` if the block found is air.
---@param pos CoordPosition
---@return boolean, Block|nil
function walkback:inspectAt(pos)
	local block = self.all_seen_blocks[helpers.keyFromTable(pos)]
	if not block then
		return false, nil
	elseif block.name =="minecraft:air" then
		return true, nil
	end
	return true, block
end

-- ============
-- Mining
-- ============
-- these should update our internal state.

--- Attempt to break the block in front of the turtle.
---
--- Requires a valid tool to be equipped on one of the sides of the turtle.
---
--- Optionally takes in a side for which tool to use.
---
--- Returns if the block was broken, and reason it was not broken if needed.
---@param side TurtleSide|nil
---@return boolean, MiningError
function walkback:dig(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.dig(side)
	if a then
		-- set the new block. Most of the time this will be air, but theoretically
		-- this could detect gravel and such falling in front of the turtle
		-- assuming it yielded long enough.
		self:inspect()
	end
	return a, b
end

--- Attempt to break the block above the turtle.
---
--- Requires a valid tool to be equipped on one of the sides of the turtle.
---
--- Optionally takes in a side for which tool to use.
---
--- Returns if the block was broken, and reason it was not broken if needed.
---@param side TurtleSide|nil
---@return boolean, MiningError
function walkback:digUp(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.digUp(side)
	if a then
		self:inspectUp()
	end
	return a, b
end

--- Attempt to break the block below the turtle.
---
--- Requires a valid tool to be equipped on one of the sides of the turtle.
---
--- Optionally takes in a side for which tool to use.
---
--- Returns if the block was broken, and reason it was not broken if needed.
---@param side TurtleSide|nil
---@return boolean, MiningError
function walkback:digDown(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.digDown(side)
	if a then
		self:inspectDown()
	end
	return a, b
end

-- ======
-- New methods
-- ======

--- Mine an adjacent block. This is a combination of already public methods, but
--- is a nice alias.
---
--- This may rotate the turtle.
---
--- Has the same return signature of `self:dig()`. If the position is not
--- adjacent, this will return `false, nil`
---@param adjacent CoordPosition
---@param side TurtleSide? -- Which tool to use.
---@return boolean, MiningError|nil
function walkback:digAdjacent(adjacent, side)
	-- Confirm this is really adjacent
	if not isPositionAdjacent(self.cur_position.position, adjacent) then
		return false, nil
	end

	local y_delta = adjacent.y - self.cur_position.position.y
	-- If the block is above or below, no need to turn.
	if y_delta ~= 0 then
		-- mine it!
		if y_delta > 0 then
			return self:digUp(side)
		else
			return self:digDown(side)
		end
	end

	-- Turn to face the block.
	-- No need to check, already confirmed we are adjacent
	self:faceAdjacentBlock(adjacent)

	-- Mine it.
	return self:dig(side)
end

-- ============
-- Placing
-- ============
-- these should update our internal state.

--- Place a block or item in front of the turtle.
---
--- Does not support text on signs.
---@return boolean, PlacementError|nil
function walkback:place()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.place()
	if a then
		self:inspect()
	end
	return a, b
end

--- Place a block or item above the turtle.
---
--- Does not support text on signs.
---@return boolean, PlacementError|nil
function walkback:placeUp()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.placeUp()
	if a then
		self:inspectUp()
	end
	return a, b
end

--- Place a block or item below the turtle.
---
--- Do note that this works for placing crops if there is a 1 block gap below
--- you and farmland.
---
--- Does not support text on signs.
---@return boolean, PlacementError|nil
function walkback:placeDown()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.placeDown()
	if a then
		self:inspectDown()
	end
	return a, b
end

-- ======
-- New methods
-- ======

--- Place a block at an adjacent position.
--- This is a combination of already public methods, but is a nice alias.
---
--- This may rotate the turtle.
---
--- Has the same return signature of `self:place()`. If the position is not
--- adjacent, this will return `false, nil`
---@param adjacent CoordPosition
---@return boolean, PlacementError|nil
function walkback:placeAdjacent(adjacent)
	-- Confirm this is really adjacent
	if not isPositionAdjacent(self.cur_position.position, adjacent) then
		return false, nil
	end

	local y_delta = adjacent.y - self.cur_position.position.y
	-- If the block is above or below, no need to turn.
	if y_delta ~= 0 then
		-- mine it!
		if y_delta > 0 then
			return self:placeUp()
		else
			return self:placeDown()
		end
	end

	-- Turn to face the block.
	-- No need to check, already confirmed we are adjacent
	self:faceAdjacentBlock(adjacent)

	-- Place it.
	return self:place()
end

-- ============
-- Equipment
-- ============

--- Attempt to equip the item in the currently selected slot on the left
--- side of the turtle.
---
--- If there is already an item equipped on that side, the turtle will swap the
--- items between the side and the currently selected slot.
---
--- If there is no item in that side, the turtle will un-equip it into the
--- currently selected slot.
---
--- Returns nothing.
---
--- Panics on attempts to equip invalid items.
---@return nil
function walkback:equipLeft()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.equipLeft()
	panic.assert(a, "Attempted to equip an invalid item! [" .. b .. "]")
end

--- Attempt to equip the item in the currently selected slot on the right
--- side of the turtle.
---
--- If there is already an item equipped on that side, the turtle will swap the
--- items between the side and the currently selected slot.
---
--- If there is no item in that side, the turtle will un-equip it into the
--- currently selected slot.
---
--- Returns nothing.
---
--- Panics on attempts to equip invalid items.
---@return nil
function walkback:equipRight()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.equipRight()
	panic.assert(a, "Attempted to equip an invalid item! [" .. b .. "]")
end

--- Returns the item that is currently equipped on the left side, if any.
---@return Item|nil
function walkback:getEquippedLeft()
	---@diagnostic disable-next-line: undefined-global
	return item_helper.detailsToItem(turtle.getEquippedLeft())
end

--- Returns the item that is currently equipped on the right side, if any.
---@return Item|nil
function walkback:getEquippedRight()
	---@diagnostic disable-next-line: undefined-global
	return item_helper.detailsToItem(turtle.getEquippedRight())
end

-- ============
-- Crafting
-- ============

--- Attempt to craft the pattern currently in the turtle's inventory.
---
--- The number of crafts can be limited. IE a limit of 2 means the recipe will
--- be ran two times, thus a stack of logs would turn into 8 planks instead of
--- 256. This does not, however, guarantee that the specified amount of crafts
--- will happen, it is simply an upper limit.
---
--- This will NOT pre-check the inventory to ensure that there are no items within
--- the edge slots, and will panic if the setup is invalid. Additionally, this
--- should not be used to _try_ recipes, you should know what you're crafting.
--- Thus a craft limit of 0, and invalid recipes will panic.
---
--- Always returns true.
---@param limit number
function walkback:craft(limit)
	panic.assert(limit <= 64 and limit >= 0, "Invalid craft limit! [" .. limit .. "]")
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.craft(limit)
	panic.assert(a, "Failed to craft! [" .. b .. "]")
	return true
end

-- ============
-- Attacking
-- ============

--- Attack in front of the turtle, optionally picking a side to use a specific tool.
---
--- Returns a boolean on wether the hit landed or not.
--- Returns `nil` if there is nothing to attack here.
---@param side TurtleSide
---@return boolean
function walkback:attack(side)
	---@type boolean, string|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, _ = turtle.attack(side)
	return a -- We only care if it worked or not.
end

--- Attack above the turtle, optionally picking a side to use a specific tool.
---
--- Returns a boolean on wether the hit landed or not.
--- Returns `nil` if there is nothing to attack here.
---@param side TurtleSide
---@return boolean|nil
function walkback:attackUp(side)
	---@type boolean, string|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, _ = turtle.attackUp(side)
	return a
end

--- Attack below the turtle, optionally picking a side to use a specific tool.
---
--- Returns a boolean on wether the hit landed or not.
--- Returns `nil` if there is nothing to attack here.
---@param side TurtleSide
---@return boolean|nil
function walkback:attackDown(side)
	---@type boolean, string|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, _ = turtle.attackDown(side)
	return a
end

-- ============
-- Fuel
-- ============

--- Returns the current fuel level of the turtle.
---
--- Always returns a number, as we assume that unlimited fuel is not turned on.
---@return number
function walkback:getFuelLevel()
	---@diagnostic disable-next-line: undefined-global
    local fuel = turtle.getFuelLevel()
	panic.assert(type(fuel) == "number", "unlimited fuel should not be enabled.")
	return fuel
end

--- Consumes item from currently select slot. Optionally takes in a limit of how
--- many items to consume.
---
--- Does not guarantee that the selected count of items will all be consumed.
---
--- If the refuel amount is set to zero, this function will return true or false
--- depending on if the item in the current slot is combustible or not.
---
--- Otherwise, returns if the turtle was refueled. Will return false if the item selected
--- is non-combustible, or if there are no items in the currently selected slot.
---@param count number?
---@return boolean, string|nil
function walkback:refuel(count)
	if count and count < 0 then
		-- Negative refueling does not work.
		return false
	end
	---@type boolean
	local a
	---@diagnostic disable-next-line: undefined-global
	a, _ = turtle.refuel(count)
	return a
end

--- Returns the maximum amount of fuel that this turtle can hold. Always returns
--- a number, as we assume infinite fuel is not enabled.
function walkback:getFuelLimit()
	---@diagnostic disable-next-line: undefined-global
	local fuel = turtle.getFuelLimit()
	panic.assert(type(fuel) == "number", "unlimited fuel should not be enabled.")
	return fuel
end


-- ========================
-- Sanity checks
-- ========================

-- Test rotations
local sanity = rotateDirection("f", "n")
panic.assert(sanity == "n", "Incorrect rotation!")
local sanity = rotateDirection("b", "n")
panic.assert(sanity == "n", "Incorrect rotation!")
local sanity = rotateDirection("u", "n")
panic.assert(sanity == "n", "Incorrect rotation!")
local sanity = rotateDirection("d", "n")
panic.assert(sanity == "n", "Incorrect rotation!")
local sanity = rotateDirection("l", sanity)
panic.assert(sanity == "w", "Incorrect rotation!")
local sanity = rotateDirection("l", sanity)
panic.assert(sanity == "s", "Incorrect rotation!")
local sanity = rotateDirection("l", sanity)
panic.assert(sanity == "e", "Incorrect rotation!")
local sanity = rotateDirection("l", sanity)
panic.assert(sanity == "n", "Incorrect rotation!")
local sanity = rotateDirection("r", sanity)
panic.assert(sanity == "e", "Incorrect rotation!")
local sanity = rotateDirection("r", sanity)
panic.assert(sanity == "s", "Incorrect rotation!")
local sanity = rotateDirection("r", sanity)
panic.assert(sanity == "w", "Incorrect rotation!")
local sanity = rotateDirection("r", sanity)
panic.assert(sanity == "n", "Incorrect rotation!")

-- Significant distance should default north
panic.assert(mostSignificantDirection(0,0) == "n", "Should default north!")

-- Facing rotation actions
local a = findFacingRotation("n", "n")
---@diagnostic disable-next-line: need-check-nil
assert(not a[1] , "Finding rotation wrong! Got: " .. tostring(a[1]))
local a = findFacingRotation("n", "e")
---@diagnostic disable-next-line: need-check-nil
assert(a[1]  == "r", "Finding rotation wrong! Got: " .. tostring(a[1]))
---@diagnostic disable-next-line: need-check-nil
local a = findFacingRotation("n", "s")
---@diagnostic disable-next-line: need-check-nil
assert(a[1]  == "r", "Finding rotation wrong! Got: " .. tostring(a[1]))
local a = findFacingRotation("n", "w")
---@diagnostic disable-next-line: need-check-nil
assert(a[1]  == "l", "Finding rotation wrong! Got: " .. tostring(a[1]))

-- ========================
-- All done!
-- ========================

-- Return walkback so methods can be called on it.
return walkback