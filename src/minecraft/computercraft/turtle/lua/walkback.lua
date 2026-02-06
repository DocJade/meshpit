-- Walkback! see walkback.

local panic = require("panic")
local helpers = require("helpers")
local block_helper = require("block")
local item_helper = require("item")

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

    --- The current walkback chain. An array of positions.
    --- Position 0 is the first step in the chain.
    ---
    --- We don't store facing direction, thus we do not guarantee that
    --- walkbacks will end you facing in the same direction that you started.
    ---@alias WalkbackChain CoordPosition[]
    ---@type CoordPosition[]
    walkback_chain = {};

    -- Hashmap of all of the positions we've seen so far in this walkback chain.
    -- Implemented as:
    -- key: string
	-- - The string is derived from casting CoordPosition to a key
	-- - via using helpers.keyFromTable(CoordPosition)
    -- value: Returns the index into the walkback_chain where this position lives.
    ---@alias ChainSeenPositions {[string]: number}
    ---@type ChainSeenPositions
    chain_seen_positions = {};

	--- Hashset of ALL positions this turtle has visited since the last time
	--- reset was called. This does not allow you to index into the walkback_chain,
	--- since it only contains booleans.
	--- 
	--- Keyed with helpers.keyFromTable(CoordPosition)
	---@alias AllSeenPositions {[string]: boolean}
	---@type AllSeenPositions
    all_seen_positions = {};

	--- Hashmap of ALL the blocks a turtle has seen since the last time reset was
	--- called. This does not have an index, as the data is not ordered.
	--- 
	--- Keyed with helpers.keyFromTable(CoordPosition)
	---@alias AllSeenBlocks {[string]: Block}
	---@type AllSeenBlocks
	all_seen_blocks = {}

	--- In the future, it may be work storing all of the items the turtle is currently holding.
	--- This would allow fast inventory lookups to see if we have an item, but would require
	--- keeping slots up to date every time an inventory modifying action occurs.
}

-- ========================
-- Type definitions
-- ========================

---@alias FacingDirection
---| "n" # North: -Z
---| "e" # East: +X
---| "s" # South: +Z
---| "w" # West: -X

--- Casting between a facing direction and a tuple (table lol) of x,z change.
---@type {[FacingDirection]: table<number, number>}
local dir_to_change = {n = {0, -1}, e = {1, 0}, s = {0, 1}, w = {-1, 0}}

--- Cast a x,z delta to a direction. Clamps values and picks the most significant
--- direction. Does not do diagonal directions.
--- 
--- If both axis are of equal length, it will prefer North.
---@param x number
---@param z number
---@return FacingDirection
function mostSignificantDirection(x,z)
	-- absolutes to get the most significant distance on an axis
	local abs_x = math.abs(x)
    local abs_z = math.abs(z)
	-- If z is greater than x, the more significant direction is either north or south.
	-- if the numbers are equal, there is no 
	if abs_z >= abs_x then
		return z > 0 and "s" or "n"
	else
		return x > 0 and "e" or "w"
	end
end

--- Casting back and forth to integer representation.
---@type string[]
local dirs = {"n", "e", "s", "w"}

---@type {[FacingDirection]: number}
local dir_to_num = {n = 1, e = 2, s = 3, w = 4}
-- `local num_to_dir` is the same as just indexing into dirs. do that.

---@alias CoordPosition {x: number, y: number, z: number}

---@alias MovementDirection
---| "f" # Forward
---| "b" # Back
---| "u" # Up
---| "d" # Down
---| "l" # Turn left
---| "r" # Turn right

--- Some turtle command take in a side parameter of the turtle, this is either
--- left, right, or nil.
---@alias TurtleSide "left"|"right"|nil


--- Movement vectors based on direction
---@type {[string]: CoordPosition}
local movement_vectors = {
    n = {
        x = 0,
        y = 0,
        z = -1
    },
    e = {
        x = 1,
        y = 0,
        z = 0
    },
    s = {
        x = 0,
        y = 0,
        z = 1
    },
    w = {
        x = -1,
        y = 0,
        z = 0
    },
    u = {
        x = 0,
        y = 1,
        z = 0
    },
    d = {
        x = 0,
        y = -1,
        z = 0
    },
}

---@alias MinecraftPosition {position: CoordPosition, facing: FacingDirection} 
---@type MinecraftPosition


--- The walkback positions that we can push and pop should not contain the
--- list of blocks we've seen, as we don't wanna forget that information when
--- pathfinding or if the walkback never gets pushed again
--- @alias PoppedWalkback {position: MinecraftPosition, chain: WalkbackChain, seen: ChainSeenPositions}
---@type PoppedWalkback

--- All possible return messages on why a turtle movement failed.
--- Values gathered from:
--- https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/common/src/main/java/dan200/computercraft/shared/turtle/core/TurtleMoveCommand.java
--- Some values are assumes to just be impossible.
---@alias MovementError
---| "Movement obstructed" -- Block is solid, or, even with pushing enabled, an entity cannot be pushed out of the way.
---| "Out of fuel" -- Self explanatory
---| "Movement failed" -- Failed for a reason outside of CC:Tweaked s control? Realistically should not happen
---| "Too low to move" -- Self explanatory
---| "Too high to move" -- Self explanatory
---| "Cannot leave the world" -- Minecraft itself considers the movement to be out of bounds. world.isInWorldBounds(). No idea how that works. 
---| "Cannot leave loaded world" -- Self explanatory. Should not occur if our chunk loading solution works correctly.
-- ---| "Cannot enter protected area" -- Apparently spawn protection related. But spawn protection no longer exists, we should never see this.
-- ---| "Cannot pass the world border" -- This is so far out that it should be impossible to ever reach this.
-- ---| "Unknown direction" -- Theoretically impossible to hit.
---@type MovementError

---@alias ItemError
---| "No space for items"
---| "No items to drop"
---| "No items to take"
---@type ItemError

---@alias UpgradeError
---| "Not a valid upgrade"
---@type UpgradeError

---@alias CraftError
---| "No matching recipes"
---@type CraftError

---@alias RefuelError
---| "No items to combust"
---| "Items not combustible"

--- This should be covered by Mining and Attacking error.
---@alias ToolError
---| "No tool to dig with"
---| "No tool to attack with"
---@type ToolError

---@alias PlacementError
---| "No items to place"
---| "Cannot place block here"
---| "Cannot place item here"
---| "Cannot place in protected area"
---@type PlacementError

---@alias MiningError
---| "No tool to dig with"
---| "Nothing to dig here"
---| "Cannot break unbreakable block"
---| "Cannot break protected block"
---| "Cannot break block with this tool"
---@type MiningError



-- ========================
-- Position and rotation helpers
-- ========================

--- Rotate a direction based on a movement direction. Does nothing if
--- the movement does not effect rotation.
--- 
--- Does not modify the original direction (as its a string),
--- returns a new direction.
--- 
---@param move_direction MovementDirection The way in which the turtle moved.
---@param original_facing FacingDirection The facing direction to transform.
---@return FacingDirection
function rotateDirection(move_direction, original_facing)
    -- This checks for for non-rotation,
    -- since the directional movements wont be found.
    if string.match(move_direction, "^[fbud]") then
        -- no change
        return original_facing
    end
    -- Index into an array based on the direction.
    local found = dir_to_num[original_facing]
    if not found then
        panic.panic("Invalid facing direction [" .. original_facing .. "]!", true)
    end
    -- Rotate the direction by offsetting into the dir table
    local change = (move_direction == "l") and -1 or 1
    return dirs[((found - 1 + change + 4) % 4) + 1]
end

--- Get the opposite facing direction from a direction.
--- 
--- Does not modify the incoming direction, as it is a string.
---@param direction FacingDirection
---@return FacingDirection opposite
function invertDirection(direction)
	local found = dir_to_num[direction]
	-- 2 rotates us 180
	return dirs[((found - 1 + 2 + 4) % 4) + 1]
end

--- Find what moves are required to face in a direction from a starting direction.
--- 
--- May return no movements in the form of an empty table if already facing
--- the correct direction.
---@param start_direction FacingDirection
---@param end_direction FacingDirection
---@return MovementDirection[]?
function findFacingRotation(start_direction, end_direction)
	local moves = {}
	if start_direction == end_direction then
		return moves
	end

	local start_num = dir_to_num[start_direction]
	local end_num = dir_to_num[end_direction]

	-- Clockwise
	local right_distance = (end_num - start_num + 4) % 4
	-- Counter
	local left_distance = (start_num - end_num + 4) % 4
	local times = math.min(right_distance, left_distance)

	-- Prefer right turns
	local turn_direction = right_distance >= left_distance and "r" or "l"

	for i = 1, times do
		moves[i] = turn_direction
	end
	return moves
end

--- Apply a transformation to a position.
--- 
--- Modifies the incoming table.
---@param origin CoordPosition The position to transform
---@param delta CoordPosition The transformation to apply
function offsetPosition(origin, delta)
    origin.x = origin.x + delta.x
    origin.y = origin.y + delta.y
    origin.z = origin.z + delta.z
end

--- Invert a position by negating all of its values.
--- 
--- Modifies the incoming table, be careful with vector tables!
---@param position CoordPosition
function invertPosition(position)
    position.x = position.x * -1
    position.y = position.y * -1
    position.z = position.z * -1
end

--- Clone a position
--- Does not modify the incoming table, or copy meta.
---@param position CoordPosition
---@return CoordPosition 
function clonePosition(position)
    local new = {
        x = position.x,
        y = position.y,
        z = position.z,
    }
    return new
end


--- Get the new position of the turtle based on a movement direction,
--- and its current facing direction.
--- 
--- Modifies the incoming position table.
--- 
--- Ignores rotation movements, as they do not move in coordinate space.
---@param direction MovementDirection The way in which the turtle moved.
---@param facing FacingDirection Our current facing direction, this is not updated.
---@param start_position CoordPosition Position to offset from.
function transformPosition(direction, facing, start_position)
    -- North -z
    -- East: +x
    -- South +z
    -- West: -x
    -- Up: +y
    -- Down: +y
    -- Skip rotations
    if string.match(direction, "^[lr]") then
        -- no change
        return
    end
    -- Up down
    if direction == "u" or direction == "d" then
        start_position.y = start_position.y + (direction == "u" and 1 or -1)
        return
    end
    -- Forward back is hard, since its based on facing direction
    -- this is why we have the lookup table
    local delta = movement_vectors[facing]
    -- Invert if we're moving backwards
    if direction == "b" then
        delta = clonePosition(delta)
        invertPosition(delta)
    end
    -- Offset
    offsetPosition(start_position, delta)
end

--- Get the taxicab distance between two positions. Will always be a positive,
--- whole integer.
---@param pos1 CoordPosition
---@param pos2 CoordPosition
---@return number
function taxicabDistance(pos1, pos2)
	-- local x = math.abs(pos1.x - pos2.x)
	-- local y = math.abs(pos1.y - pos2.y)
	-- local z = math.abs(pos1.z - pos2.z)
	-- return x + y + z
	return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y) + math.abs(pos1.z - pos2.z)
end

--- Check is a position is directly adjacent to another position.
--- 
--- Does not consider diagonals to be adjacent,
--- positions must share a block face, and
--- positions are not adjacent to themselves.
---@param pos1 CoordPosition
---@param pos2 CoordPosition
---@return boolean
function isPositionAdjacent(pos1, pos2)
	-- Same position?
	-- Too far away?
	-- And adjacent, all in one check! 
	return taxicabDistance(pos1, pos2) == 1
end


--- From our current position, deduce what actions need to be taken to move to
--- an adjacent position.
--- 
--- Uses global state for getting current position, does not modify it.
--- 
--- Can return multiple movement directions, as moving laterally requires a turn,
--- then a movement.
--- 
--- returns `nil` if the destination position is not adjacent to the turtle. The
--- turtle's current position is also not considered adjacent, as no move is
--- required to get to that position.
---@param destination CoordPosition
---@return nil|MovementDirection[]
function deduceAdjacentMove(destination)
	-- Make sure the position is adjacent to our current position, else
	-- this would cause us to move forwards for no reason.
	if not isPositionAdjacent(walkback.cur_position.position, destination) then
		return nil
	end

	-- Only one of the 3 directions can have a value of +-1.
	local x_delta = destination.x - walkback.cur_position.position.x
	local y_delta = destination.y - walkback.cur_position.position.y
	local z_delta = destination.z - walkback.cur_position.position.z

	-- If the movement is vertical, the facing direction does not matter
	if y_delta ~= 0 then
		return {y_delta == -1 and "d" or "u"}
	end

	-- Determine the cardinal direction of the move
	local move_direction = mostSignificantDirection(x_delta, z_delta)

	-- Skip rotation if we're facing in the opposite direction, since we
	-- can just move backwards.
	local cur_facing = walkback.cur_position.facing
	if move_direction == invertDirection(cur_facing) then
		return {"b"}
	end

	-- Create a move set.
	---@type MovementDirection[]
	local movements = {}

	-- Rotate if needed
	local rotations = findFacingRotation(cur_facing, move_direction) or {}
	for i, v in ipairs(rotations) do
		movements[i] = v
	end

	-- Move forwards into that position.
	movements[#movements +1 ] = "f"

	return movements
end

-- ========================
-- Internal Methods
-- ========================

--- Record a movement based on a move direction.
--- This should be called after the move has successfully finished.
--- 
--- Modifies global state. (Updates our position and walkback steps)
---@param direction MovementDirection The way in which the turtle moved.
function recordMove(direction)
    -- If this is only a rotation, we can skip all of the costly
    -- lookups, since we do not care about facing direction.
    -- Save the previous rotation
    local original_facing = walkback.cur_position.facing
    -- Possibly apply the rotation
    walkback.cur_position.facing = rotateDirection(direction, original_facing)
    if walkback.cur_position.facing ~= original_facing then
        -- Only rotated. No need to record this movement.
        return
    end

    -- Movement is positional
    -- Apply the transformation,
    transformPosition(direction, walkback.cur_position.facing, walkback.cur_position.position)
    
	-- Trim movement if needed.
	-- If we trimmed, that means the end of the chain is already our end
	-- position and we can skip adding the new step.
	if trimPosition() then
		return
	end

    -- Step is not currently in the chain. Add it, and we're done!
    addStep()
end

--- Checks if position overlaps with 
--- 
--- Does not put the final position on the walkback, you are expected to
--- put it on yourself afterwards.
---
--- Takes no parameters as it operates on globals only.
--- 
--- Returns true if trimming occurred.
--- 
--- Modifies global state. (Updates walkback_chain, seen_positions)
---@return boolean
function trimPosition()
	-- if the end of the chain is already our current position, we can skip all of this.
	if helpers.deepEquals(walkback.cur_position.position, walkback.walkback_chain[#walkback.walkback_chain]) then
		return true -- we "trimmed" since we didn't move.
	end


    -- Find the position within the walkback that this position is at.
	local current_pos_key = helpers.keyFromTable(walkback.cur_position.position)
	if not current_pos_key then
		panic.panic("Position not key-able!")
		current_pos_key = "" -- never reached, purely for linter
	end

    local index = walkback.chain_seen_positions[current_pos_key]
    if index == nil then
        -- Have not seen this position before, no need for trimming.
        return false
    end
    -- We have already visited this position, we will remove all movement
    -- that occurs after it. (so we add one to skip the current position).
	-- If the index is past the end of the table,
    local slice = helpers.slice_array(walkback.walkback_chain, index + 1, #walkback.walkback_chain)
    for i, pos in ipairs(slice) do
        -- Remove from the hashset
		local key = helpers.keyFromTable(pos)
		if not key then
			panic.panic("Position not key-able!")
			key = "" -- never reached, purely for linter
		end
        walkback.chain_seen_positions[key] = nil
        -- Remove the position from the chain. This is safe to modify in place like this, since
        -- the deleted values will only be fully dropped once all references are dropped to it,
        -- and we are the only ones holding references to it here.
		-- This will nil out all the way to the end, thus no gaps are made.
        walkback.walkback_chain[index + i] = nil
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
function addStep()
    -- Make sure we haven't already seen this position
	local current_pos_key = helpers.keyFromTable(walkback.cur_position.position)
	if not current_pos_key then
		panic.panic("Position not key-able!")
		current_pos_key = "" -- never reached, purely for linter
	end

    if walkback.chain_seen_positions[current_pos_key] ~= nil then
        panic.panic("Tried to add a position to the walkback_chain that we've already seen!")
    end
    -- Add position to the end of the chain
    walkback.walkback_chain[#walkback.walkback_chain + 1] = walkback.cur_position.position

    -- Add it to the hashset as an index into the chain.
    walkback.chain_seen_positions[current_pos_key] = #walkback.walkback_chain

	-- Add it to the all seen positions hashset.
	-- This is fine if it overwrites an already seen value, since that has no effect.
	walkback.all_seen_positions[current_pos_key] = true
end

--- Perform a turtle movement based off of a MovementDirection.
---@param movement MovementDirection
---@return boolean, MovementError|nil
function doMovement(movement)
	-- No match statements yay.
	-- Ordered on what i presume to be the most common movement cases.
	local result
	local reason
	if movement == "f" then
		result, reason = walkback.forward()
	elseif movement == "u" then
		result, reason = walkback.up()
	elseif movement == "d" then
		result, reason = walkback.down()
	elseif movement == "b" then
		result, reason = walkback.back()
	elseif movement == "r" then -- right is preferred.
		result, reason = walkback.turnRight()
	elseif movement == "l" then
		result, reason = walkback.turnLeft()
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
function getAdjacentBlock(direction)
	local pos = walkback.cur_position.position
	local facing = walkback.cur_position.facing
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


--- Document a block that we have seen and store it in walkback.all_seen_blocks.
--- Will overwrite whatever block has already been seen in that position. Use this
--- method when destroying blocks (setting them to air), when placing blocks, or
--- when scanning surroundings.
--- 
--- Does not clone the block. Thus callers MUST NOT modify it after storing.
--- 
--- Modifies global state. (Updates all_seen_blocks)
---@param position CoordPosition
---@param block Block
function saveBlock(position, block)
	-- We can assert this returned key is not nil, since coordinate positions
	-- are only numbers.
	local key = helpers.keyFromTable(position)
	---@cast key string
	walkback.all_seen_blocks[key] = block
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
--- @param facing FacingDirection Facing direction
--- @return nil
function walkback.setup(x, y, z, facing)
    walkback.cur_position.position.x = x
    walkback.cur_position.position.y = y
    walkback.cur_position.position.z = z
    walkback.cur_position.facing = facing
	-- Add the first step, which our current position.
	addStep()
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
function walkback.mark()
    -- Cancel if we have any internal state.
    if next(walkback.walkback_chain) ~= nil and next(walkback.chain_seen_positions) ~= nil then
        return false
    end
    -- Reset!
    local x = walkback.cur_position.position.x
    local y = walkback.cur_position.position.y
    local z = walkback.cur_position.position.z
    local facing = walkback.cur_position.facing
    walkback.setup(x, y, z, facing)
    return true
end

--- Rewind the turtle to the marked position.
--- You should ensure you have enough fuel for the full walkback first.
--- 
--- Returns a bool, string|nil pair denoting success or a failure reason.
--- 
--- Will return `"Not enough fuel"` if the rewind could never possibly work due
--- to being too long.
---@return boolean, MovementError|"Not enough fuel"|nil
function walkback.rewind()
    -- Composed of other methods for implementation simplicity! :D
    -- Pre-check if we have enough fuel. If we don't, then we won't
    -- even start.
    local fuel_level = walkback.getFuelLevel()
	local cost = walkback.cost()
	if cost > fuel_level then
		return false, "Not enough fuel"
	end
	-- Run walkback steps until we run out of steps.
	while type(walkback.previousPosition()) ~= "nil" do
		local ok, result = walkback.stepBack()
		if not ok then
			return false, result
		end
	end

	-- All done!
	return true, nil
end

--- Rewind the position of the turtle a single step.
--- 
--- Returns a bool, string|nil pair denoting success or a failure reason.
--- 
--- Failure reasons:
--- "fuel" - No fuel, cannot move.
--- "obstacle" - Could not complete walkback due to a block being in the way.
---@return boolean, MovementError|nil
function walkback.stepBack()
	-- The previous position should always be adjacent, we're just gonna assume
	-- that entirely here for speed. Good luck!
	local dest = helpers.unwrap(walkback.previousPosition())
	-- There should be at least one move.
	local moves = helpers.unwrap(deduceAdjacentMove(dest))
	for _, move in ipairs(moves) do
		local ok, result = doMovement(move)
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
function walkback.previousPosition()
    return walkback.walkback_chain[#walkback.walkback_chain - 1]
end

--- How much fuel it would cost to run the full rewind
--- from the current position.
--- 
---@return number
function walkback.cost()
	-- The fuel cost is the same as the number of moves to make, minus 1 for
	-- the current position.
	return #walkback.walkback_chain - 1
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
function walkback.pop()
	-- Cancel if there is currently no chain.
	if walkback.previousPosition() == nil then
		return nil
	end

	local position_copy = helpers.deepCopy(walkback.cur_position)
	local chain_copy = helpers.deepCopy(walkback.walkback_chain)
	local seen_copy = helpers.deepCopy(walkback.chain_seen_positions)
	---@type PoppedWalkback
	local copy = {
		position = position_copy,
		chain = chain_copy,
		seen = seen_copy
	}
	-- Remove the old walkback
	-- We do not modify the current position
	walkback.walkback_chain = {}
	walkback.chain_seen_positions = {}
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
function walkback.push(state)
	-- Do we have any current steps?
	if walkback.previousPosition() ~= nil then
		return false
	end
	-- Are we in the right position?
	if not helpers.deepEquals(walkback.cur_position, state.position) then
		return false
	end

	-- Push that on!
	walkback.walkback_chain = state.chain
	walkback.chain_seen_positions = state.seen
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
function walkback.posQuery(position, full)
	local check_full = full or false
	if check_full then
		-- We don't need to check the current walkback, as this
		-- also contains it.
		return walkback.all_seen_positions[position] ~= nil
	end
	-- current walkback
	return walkback.chain_seen_positions[position] ~= nil
end

--- COMPLETELY resets the state of walkback, including ALL data such as
--- previously seen blocks. Only do this AFTER uploading information to the
--- control computer, as we really really want that block data, otherwise we
--- wasted a whole bunch of time and memory.
function walkback.hardReset()
	walkback.all_seen_positions = {}
	walkback.chain_seen_positions = {}
	walkback.walkback_chain = {}
	-- Doesn't remove the current position for hopefully obvious reasons.
end

--- Returns the full walkback state of this turtle as a json'ed table of all of
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
---@return string json See function definition for format.
function walkback.dataJson()
	return helpers.serializeJSON(walkback)
end

--- Returns all of the items the turtle currently has in its inventory as an array.
--- Empty slots are null.
---@return string json See function definition for format.
function walkback.inventoryJSON()
	---@type Item[]
	local items = {}
	for i= 1, 16 do
		items[i] = walkback.getItemDetail(i, true)
		-- Fix empty slots
		if items[i] == nil then
			---@diagnostic disable-next-line: undefined-global
			items[i] = textutils.json_null
		end
	end
	return helpers.serializeJSON(items)
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
function walkback.blockQuery(position, and_air)
	---@type Block|nil
	local found = walkback.all_seen_blocks[helpers.keyFromTable(position)]
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

--- Move the turtle forwards.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.forward()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.forward()
	if a then
		recordMove("f")
	end
	return a, b
end

--- Move the turtle backwards. (NOT going back a step in the walkback chain)
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.back()
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.back()
	if a then
		recordMove("b")
	end
	return a, b
end

--- Move the turtle upwards.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.up() 
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.up()
	if a then
		recordMove("u")
	end
	return a, b
end

--- Move the turtle downwards.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.down() 
	---@type boolean, MovementError|nil
	local a, b
	---@diagnostic disable-next-line: undefined-global
	a, b = turtle.down()
	if a then
		recordMove("d")
	end
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
function walkback.turnLeft()
	---@diagnostic disable-next-line: undefined-global
	turtle.turnLeft()
	recordMove("l")
	return true, nil
end

--- Turns the turtle to the right. 
--- 
--- This operation cannot fail, but has the same return format as the other
--- movement actions for ease of use.
---@return true, nil
function walkback.turnRight()
	---@diagnostic disable-next-line: undefined-global
	turtle.turnRight()
	recordMove("r")
	return true, nil
end

-- ======
-- New methods
-- ======

-- These scan post-movement.

--- Move the turtle forwards.
--- 
--- Additionally scans the blocks around the turtle post-movement.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.forwardScan()
	local a, b = walkback.forward()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	-- Scan time
	walkback.turnLeft()
	walkback.inspect()
	
	walkback.turnRight()
	walkback.inspect()
	walkback.turnRight()
	walkback.inspect()
	
	walkback.turnLeft()

	walkback.inspectUp()
	walkback.inspectDown()

	return a, b
end

--- Move the turtle backwards. (NOT going back a step in the walkback chain)
--- 
--- Additionally scans the blocks around the turtle post-movement.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.backScan()
	-- Fairly niche movement, mostly for rewinding.
	-- To scan behind us we need to make a full rotation anyways, so
	-- we can just use the full spin scan.
	local a, b = walkback.back()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	walkback.spinScan()
	return a, b
end

--- Move the turtle upwards.
--- 
--- Additionally scans the blocks around the turtle post-movement.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.upScan()
	-- The blocks on every side of use are different now, spin
	local a, b = walkback.up()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	walkback.spinScan()
	return a, b
end

--- Move the turtle downwards.
--- 
--- Additionally scans the blocks around the turtle post-movement.
--- 
--- Returns a boolean on wether the move completed or not,
--- and a string if the movement failed.
---@return boolean, MovementError|nil
function walkback.downScan()
	-- The blocks on every side of use are different now, spin
	local a, b = walkback.down()
	if not a then
		-- Cannot scan because we did not move.
		return a, b
	end
	walkback.spinScan()
	return a, b
end

--- Spins the turtle around and documents every block around it.
--- Finishes in the same position and facing direction the turtle started in.
---@return nil
function walkback.spinScan()
	-- We'll get the front on the final turn
	walkback.turnRight() -- We prefer clockwise turns.
	walkback.inspect() -- Save the block data internally.
	walkback.turnRight()
	walkback.inspect()
	walkback.turnRight()
	walkback.inspect()
	walkback.turnRight()
	walkback.inspect()
	walkback.inspectUp()
	walkback.inspectDown()
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
function walkback.drop(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = walkback.getItemCount(walkback.getSelectedSlot())
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
function walkback.dropUp(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = walkback.getItemCount(walkback.getSelectedSlot())
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
function walkback.dropDown(limit)
	panic.assert(limit <= 64 and limit >= 0, "Tried to drop an invalid amount of items! [" .. limit .. "]")
	local actual = walkback.getItemCount(walkback.getSelectedSlot())
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
--- Accepted values are 1-16.
---@param slot number
---@return boolean
function walkback.select(slot)
	panic.assert(slot >= 17 or slot <= 0, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	---@diagnostic disable-next-line: undefined-global
	turtle.select(slot)
	return true
end

--- Get the number of items in a slot. Defaults to the currently selected slot.
--- 
--- Should have no difference in CPU time cost than getItemDetail() with
--- detailed set to false. So if you are going to manipulate this item further,
--- consider loading the slot's item directly.
---@param slot number
---@return number
function walkback.getItemCount(slot)
	panic.assert(slot >= 17 or slot <= 0, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.getItemCount(slot)
end

--- Get how many more items of the same type can be stored in a slot. Defaults
--- to the currently selected slot.
--- 
--- IE if a slot has 13 dirt in it, this will return 51.
--- 
--- Returns 64 for empty slots.
---@param slot number
---@return number
function walkback.getItemSpace(slot)
	panic.assert(slot >= 17 or slot <= 0, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
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
function walkback.suck(count)
	count = count or 64
	panic.assert(count <= 64 and count >= 0, "Invalid suck amount! [" .. count .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.suck()
end

--- See suck(), but up!
---@param count number
---@return boolean, ItemError|nil
function walkback.suckUp(count)
	count = count or 64
	panic.assert(count <= 64 and count >= 0, "Invalid suck amount! [" .. count .. "]")
	---@diagnostic disable-next-line: undefined-global
	return turtle.suckUp()
end

--- See suck(), but down!
---@param count number
---@return boolean, ItemError|nil
function walkback.suckDown(count)
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
function walkback.transferTo(slot, count)
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
function walkback.compareTo(slot)
	panic.assert(16 >= slot and slot >= 1, "Tried to index outside of the allowed slot range! [" .. slot .. "]")
	-- Already bounds checked, this will not throw
	---@diagnostic disable-next-line: undefined-global
	return turtle.compareTo(slot)
end

--- Returns what slot is currently selected.
--- 
--- Returns a number between 1 and 16 inclusive.
---@return number
function walkback.getSelectedSlot()
	---@diagnostic disable-next-line: undefined-global
	return turtle.getSelectedSlot()
end

--- Get information about the item sin the given slot. Slot defaults to the
--- currently selected slot.
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
function walkback.getItemDetail(slot, detailed)
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
function walkback.transferFromSlotTo(source_slot, destination_slot, count)
	-- Remember the old slot
	local old = walkback.getSelectedSlot()

	-- Do the move.
	walkback.select(source_slot)
	local result = walkback.transferTo(destination_slot, count)

	-- go back
	walkback.select(source_slot)
	walkback.select(old)
	return result
end

--- Checks if two arbitrary slots have the same item (by name).
---@param slot_a number
---@param slot_b number
---@return boolean
function walkback.compareTwoSlots(slot_a, slot_b)
	-- Slot assertions happen in sub-calls
	-- Save the active slot
	local old = walkback.getSelectedSlot()
	-- Do the comparison
	walkback.select(slot_a)
	local result = walkback.compareTo(slot_b)
	-- go back
	walkback.select(old)
	return result
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
function walkback.detect()
	return walkback.inspect() ~= nil
end

--- Check if there is a solid block in front of the turtle. Solid refers to
--- any block that we cannot move into. Unlike the base CC:Tweaked methods, this
--- will return false on fluids, as we can move through those.
---@return boolean
function walkback.detectUp()
	return walkback.inspectUp() ~= nil
end

--- Check if there is a solid block in front of the turtle. Solid refers to
--- any block that we cannot move into. Unlike the base CC:Tweaked methods, this
--- will return false on fluids, as we can move through those.
---@return boolean
function walkback.detectDown()
	return walkback.inspectDown() ~= nil
end

-- ======
-- New methods
-- ======

--- Check if a block at a position is solid.
--- 
--- Returns `nil` if we have not seen that block.
---@param pos CoordPosition
---@return boolean|nil
function walkback.detectAt(pos)
	return walkback.blockQuery(pos) ~= nil
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
function walkback.compare()
	-- We don't use the version built into computercraft as it does RNG rolls
	-- with block loot-tables and thats stupid.
	-- We assume item names == block names
	local block = walkback.inspect()
	local item = walkback.getItemDetail()
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
function walkback.compareUp()
	local block = walkback.inspectUp()
	local item = walkback.getItemDetail()
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
function walkback.compareDown()
	local block = walkback.inspectDown()
	local item = walkback.getItemDetail()
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
function walkback.compareAt(pos)
	local contained, block = walkback.inspectAt(pos)
	if (not contained) or (block == nil) then
		return false
	end
	local item = walkback.getItemDetail()
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
function walkback.inspect()
	local pos = getAdjacentBlock("f")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspect()
	local block = block_helper.detailsToBlock(b, pos)
	saveBlock(pos, block)
	if block.name ~= "minecraft:air" then
		return block
	end
end

--- Get information about the block above the turtle.
--- 
--- Returns `nil` if the block in front of the turtle is air.
---@return Block|nil
function walkback.inspectUp()
	local pos = getAdjacentBlock("u")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspectUp()
	local block = block_helper.detailsToBlock(b, pos)
	saveBlock(pos, block)
	if block.name ~= "minecraft:air" then
		return block
	end
end

--- Get information about the block below the turtle.
--- 
--- Returns `nil` if the block in front of the turtle is air.
---@return Block|nil
function walkback.inspectDown()
	local pos = getAdjacentBlock("d")
	---@type table|string
	local b
	---@diagnostic disable-next-line: undefined-global
	_, b = turtle.inspectDown()
	local block = block_helper.detailsToBlock(b, pos)
	saveBlock(pos, block)
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
function walkback.inspectAt(pos)
	local block = walkback.all_seen_blocks[helpers.keyFromTable(pos)]
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
function walkback.dig(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.dig(side)
	if a then
		-- set the new block. Most of the time this will be air, but theoretically
		-- this could detect gravel and such falling in front of the turtle 
		-- assuming it yielded long enough.
		walkback.inspect()
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
function walkback.digUp(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.digUp(side)
	if a then
		walkback.inspectUp()
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
function walkback.digDown(side)
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.digDown(side)
	if a then
		walkback.inspectDown()
	end
	return a, b
end

-- ============
-- Placing
-- ============
-- these should update our internal state.

--- Place a block or item in front of the turtle.
--- 
--- Does not support text on signs.
---@return boolean, PlacementError|nil
function walkback.place()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.place()
	if a then
		walkback.inspect()
	end
	return a, b
end

--- Place a block or item above the turtle.
--- 
--- Does not support text on signs.
---@return boolean, PlacementError|nil
function walkback.placeUp()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.placeUp()
	if a then
		walkback.inspectUp()
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
function walkback.placeDown()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.placeDown()
	if a then
		walkback.inspectDown()
	end
	return a, b
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
function walkback.equipLeft()
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
function walkback.equipRight()
	---@diagnostic disable-next-line: undefined-global
	local a, b = turtle.equipRight()
	panic.assert(a, "Attempted to equip an invalid item! [" .. b .. "]")
end

--- Returns the item that is currently equipped on the left side, if any.
---@return Item|nil
function walkback.getEquippedLeft()
	---@diagnostic disable-next-line: undefined-global
	return item_helper.detailsToItem(turtle.getEquippedLeft())
end

--- Returns the item that is currently equipped on the right side, if any.
---@return Item|nil
function walkback.getEquippedRight()
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
function walkback.craft(limit)
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
function walkback.attack(side)
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
function walkback.attackUp(side)
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
function walkback.attackDown(side)
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
function walkback.getFuelLevel()
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
function walkback.refuel(count)
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
function walkback.getFuelLimit()
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
assert(findFacingRotation("n", "n")[1] == nil, "Finding rotation wrong!")
assert(findFacingRotation("n", "e")[1] == "r", "Finding rotation wrong!")
assert(findFacingRotation("n", "s")[2] == "r", "Finding rotation wrong!")
assert(findFacingRotation("n", "w")[1] == "l", "Finding rotation wrong!")

-- ========================
-- All done!
-- ========================

-- Return walkback so methods can be called on it.
return walkback