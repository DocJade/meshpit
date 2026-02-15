--- This is purely for linting. This file does not need to be imported, or
--- uploaded to computers within computercraft. As there is no actual code in
--- here.


--- ===============
--- Directional aliases
--- ===============

--- The four cardinal directions.
--- @alias CardinalDirection
--- | "n" -- North: -Z
--- | "e" -- East: +X
--- | "s" -- South: +Z
--- | "w" -- West: -X

--- All directions, including up and down. This is used mostly for movement and
--- rotation, however, left and right are occasionally used to mean a lateral
--- left or right translation instead of rotation.
--- @alias MovementDirection
--- | "f" -- Forward
--- | "b" -- Back
--- | "u" -- Up
--- | "d" -- Down
--- | "l" -- Turn left
--- | "r" -- Turn right

--- ===============
--- Positional aliases
--- ===============

--- A position in 3D space. Does not contain facing information.
--- @alias CoordPosition {x: number, y: number, z: number}

--- A position within the minecraft world, with an accompanying facing direction.
--- @alias MinecraftPosition {position: CoordPosition, facing: CardinalDirection}

--- ===============
--- Turtle-specific aliases
--- ===============

--- The side parameter of turtle commands. References the tool equipped on one
--- side of the turtle. In every function where this is used, the appropriate
--- side will be picked automatically based on the action and equipped tools.
--- @alias TurtleSide "left"|"right"|nil

--- All possible return messages on why a turtle movement failed.
--- Values gathered from:
--- https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/common/src/main/java/dan200/computercraft/shared/turtle/core/TurtleMoveCommand.java
--- Some values are assumes to just be impossible.
--- @alias MovementError
--- | "Movement obstructed" -- Block is solid, or, even with pushing enabled, an entity cannot be pushed out of the way.
--- | "Out of fuel" -- Self explanatory
--- | "Movement failed" -- Failed for a reason outside of CC:Tweaked s control? Realistically should not happen
--- | "Too low to move" -- Self explanatory
--- | "Too high to move" -- Self explanatory
--- | "Cannot leave the world" -- Minecraft itself considers the movement to be out of bounds. world.isInWorldBounds(). No idea how that works.
--- | "Cannot leave loaded world" -- Self explanatory. Should not occur if our chunk loading solution works correctly.
-- --- | "Cannot enter protected area" -- Apparently spawn protection related. But spawn protection no longer exists, we should never see this.
-- --- | "Cannot pass the world border" -- This is so far out that it should be impossible to ever reach this.
-- --- | "Unknown direction" -- Theoretically impossible to hit.
--- @type MovementError

--- @alias ItemError
--- | "No space for items"
--- | "No items to drop"
--- | "No items to take"
--- @type ItemError

--- @alias UpgradeError
--- | "Not a valid upgrade"
--- @type UpgradeError

--- @alias CraftError
--- | "No matching recipes"
--- @type CraftError

--- @alias RefuelError
--- | "No items to combust"
--- | "Items not combustible"

---  This should be covered by Mining and Attacking error.
--- @alias ToolError
--- | "No tool to dig with"
--- | "No tool to attack with"
--- @type ToolError

--- @alias PlacementError
--- | "No items to place"
--- | "Cannot place block here"
--- | "Cannot place item here"
--- | "Cannot place in protected area"
--- @type PlacementError

--- @alias MiningError
--- | "No tool to dig with"
--- | "Nothing to dig here"
--- | "Cannot break unbreakable block"
--- | "Cannot break protected block"
--- | "Cannot break block with this tool"
--- @type MiningError


--- ===============
--- Walkback-related aliases
--- ===============

--- The walkback positions that we can push and pop should not contain the
--- list of blocks we've seen, as we don't wanna forget that information when
--- path-finding or if the walkback never gets pushed again
--- @alias PoppedWalkback {position: MinecraftPosition, chain: WalkbackChain, seen: ChainSeenPositions}

--- The current walkback chain. An array of positions.
--- Position 0 is the first step in the chain.
---
--- We don't store facing direction, thus we do not guarantee that
--- walkbacks will end you facing in the same direction that you started.
--- @alias WalkbackChain CoordPosition[]

-- Hashmap of all of the positions we've seen so far in this walkback chain.
-- Implemented as:
-- key: string
-- - The string is derived from casting CoordPosition to a key
-- - via using helpers.keyFromTable(CoordPosition)
-- value: Returns the index into the walkback_chain where this position lives.
--- @alias ChainSeenPositions {[string]: number}

--- Hashset of ALL positions this turtle has visited since the last time
--- reset was called. This does not allow you to index into the walkback_chain,
--- since it only contains booleans.
---
--- Keyed with helpers.keyFromTable(CoordPosition)
--- @alias AllSeenPositions {[string]: boolean}

--- Hashmap of ALL the blocks a turtle has seen since the last time reset was
--- called. This does not have an index, as the data is not ordered.
---
--- Keyed with helpers.keyFromTable(CoordPosition)
---@alias AllSeenBlocks {[string]: Block}