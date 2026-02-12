# Walkback
Calling turtle methods directly is forbidden, thus we have `walkback` instead. Walkback is in charge of keeping track of:
- The previous positions of the turtle.
- Movement.
- Documenting all blocks surrounding a turtle after moving.
- Breaking and placing blocks.
- Inventory management
- Everything else that `turtle` can do.

Since all turtle-related calls have to go through walkback, this is a great place for us to yield to other OS tasks and do other system actions, such as re-trying sending messages out the modem.

Do note that moving between positions have rotations associated with them, but when calling rewinding functions, the rewind does not stop until it hits a new xyz position.

# Walkback methods
As walkback is our primary method of movement, it also keeps track of all of our movement for use in the main walkback methods.
## New methods
### Initialization
- `walkback.setup(x, y, z, facing)`
- - sets our initial position. Should only be called once!
### Rewind related
- `walkback.mark()`
- - This sets the new start of the walkback chain, and clears all previous stored positions. This completely resets walkback to be ready to start tracking again.
- - Returns true in the base case.
- - Returns false if marking fails.
- `walkback.rewind()`
- - Calling this will start rewinding to the marked position.
- - Returns true in the base case.
- - Returns false if rewinding to the marked position fails. This does not clear the remaining steps that need to be taken to get back to the marked point, but chances are, there is some obstacle preventing the rewind.
- `walkback.stepBack()`
- - Rewinds the position of the turtle back a single time to move to its previous position.
- - Returns true in the base case, or false if the rewinding fails.
- `walkback.previousPosition()`
- - Returns the previous position the turtle occupied, if one exists.
- - Returns nil if there is no previous position. Otherwise returns a `position`
- - This does not remove the previous position from the walkback list, and making a movement to the previous position manually is safe, however you should prefer to use `step_back()`.
- `walkback.cost()`
- - How much fuel it would cost to run the rewind from our current position.
- - Returns a number, or if there is no cost to rewind, zero.
- `walkback.pop()`
- - Pops the current walkback movement state. Do note that this returns ALL movement, not just the previous movement.
- - This can be used to store walkbacks for use later. For example, after finding a position to start strip mining from, you can pop the walkback stack to store how we got in the mine, then mark a new inital position to allow walking back to this position after a mining trip, then after rewinding, push the old walkback and rewind that to get out of the mine entirely.
- - Returns a `walkback_state` or `nil` if there is no current walkback.
- `walkback.push(walkback_state)`
- - Pushes a walkback state into the walkback runner.
- - Returns true, unless a walkback state is already stored within the turtle, in which case it returns `false`
- `walkback.posQuery(position, all)`
- - Checks if a given position is already within the walkback state.
- - If all is set, all positions within the buffer, even ones that are not in the current walkback, are checked against.
- - - This can be used to see if a turtle has (within reason, the previous position buffer does eventually discard old values) _ever_ been at a position.
- - Returns a boolean.
- `walkback.hardReset()`
- - This COMPLETELY resets the state of walkback, including ALL data, such as previously seen blocks. ONLY DO THIS AFTER UPLOADING THIS INFORMATION TO THE CONTROL COMPUTER!
- - Returns nothing.
- `walkback.dataJson()`
- - This will json-ify all of the walkback data into a string. Do note that this does not clear data, so calling this is safe to do so in any situation, although possibly slow.

### Block data related
- `walkback.blockQuery(position, and_air)`
- - This function checks if the walkback data contains information about what block exists at a position.
- - If the requested target block is directly next to the turtle, regardless if we have stored it or not, the turtle will rotate to face the block if needed, document the block, then rotate back to its original position. Such that we can return the most up-to-date information on that block.
- - Returns `nil` if block is not documented, or a `Block` if a block has been logged at that position, unless the block is air, in which case this will still return `nil`, UNLESS and_air is true.

### Position related
- `walkback.getAdjacentBlock(direction)`
- - Takes in a coordinate and returns the position adjacent to a turtle in the given direction.
- `walkback.clonePosition(CoordPosition)`
- - Makes a copy of a position, cheaply.
- `walkback.isPositionAdjacent(CoordPosition, CoordPosition)`
- - Check if two positions are adjacent. Adjacent positions share a block face.

## Movement functions
All of the base movement functions internally call the `turtle` equivilant function, thus the return types are the same as they are listed on the cc:tweaked wiki.
As the turtle travels, it will automatically scan the block forwards, up, and down to document them. However, there are additional scanning movement options for if you want to scan left and right as well.
- `walkback.forward()`
- `walkback.back()`
- `walkback.up()`
- `walkback.down()`
- `walkback.turnLeft()`
- `walkback.turnRight()`

### New methods
These methods also scan left and right on movement.
- `walkback.forwardScan()`
- `walkback.backScan()`

Up and down scans do a full rotation of the turtle to get every side.
- `walkback.upScan()`
- `walkback.downScan()`

A generic scan that does a full 360. Returns nothing and does not move the turtle, and maintains facing angle.
- `walkback.spinScan()`

Turn to face a specific cardinal direction.
- `walkback.turnToFace()`

Turns the turtle to face towards an adjacent block.
- `walkback.faceAdjacentBlock(CoordPosition)`

Moves the turtle into an adjacent position
- `walkback.moveAdjacent(CoordPosition)`

## Inventory functions
None of these have been altered from the normal `turtle` call. This is simply a layer of indirection.
- `walkback.drop([count])`
- `walkback.dropUp([count])`
- `walkback.dropDown([count])`
- `walkback.select(slot)`
- `walkback.getItemCount([slot])`
- `walkback.getItemSpace([slot])`
- `walkback.suck([count])`
- `walkback.suckUp([count])`
- `walkback.suckDown([count])`
- `walkback.compareTo(slot)`
- `walkback.transferTo(slot [, count])`
- `walkback.getSelectedSlot()`
- `walkback.getItemDetail([slot [, detailed]])`

### New methods
- `walkback.transferFromSlotTo(slot, slot, [count])
- - Transfers items between two arbitrary slots.
- `walkback.compareTwoSlots(slot, slot, [count])
- - Runs the comparison check against 2 arbitrary slots.

## Environment detection
These methods are slightly altered to also return `false` on fluids, as detect should be used for movement checks. Secretly calls inspect() under the hood to update our block list.
- `walkback.detect()`
- `walkback.detectUp()`
- `walkback.detectDown()`

### New methods
- `walkback.detectAt(pos)`
- - Check if a block at a position is solid.
- - Returns `nil` if we have not seen that block.

## Block comparison
None of these have been altered from the normal `turtle` call.
- `walkback.compare()`
- `walkback.compareUp()`
- `walkback.compareDown()`

### New methods
- `walkback.compareAt(pos)`
- - Same as the other compare methods, but checking a position instead of a side.
- - Returns `nil` if we have not seen that block.

## Block inspection
None of these have been altered from the normal `turtle` call.
- `walkback.inspect()`
- `walkback.inspectUp()`
- `walkback.inspectDown()`

### New methods
- `walkback.inspectAt(pos1)`
- - Same as the other inspect methods, but checking a position instead of a side.
- - The first returned boolean will be `nil` if we have not seen that position.

## Mining
None of these have been altered from the normal `turtle` call.
- `walkback.dig([side])`
- `walkback.digUp([side])`
- `walkback.digDown([side])`

### New methods
- `walkback.digAdjacent([side])`
- - Digs an adjacent block.

## Placing
None of these have been altered from the normal `turtle` call.
- `walkback.place([text])`
- `walkback.placeUp([text])`
- `walkback.placeDown([text])`

### New methods
- `walkback.placeAdjacent([side])`
- - Place a block at an adjacent position.

## Equipment
None of these have been altered from the normal `turtle` call.
- `walkback.equipLeft()`
- `walkback.equipRight()`
- `walkback.getEquippedLeft()`
- `walkback.getEquippedRight()`

## Crafting
None of these have been altered from the normal `turtle` call.
- `walkback.craft([limit=64])`

## Attacking
None of these have been altered from the normal `turtle` call.
- `walkback.attack([side])`
- `walkback.attackUp([side])`
- `walkback.attackDown([side])`

## Fuel
None of these have been altered from the normal `turtle` call.
- `walkback.getFuelLevel()`
- `walkback.refuel([count])`
- `walkback.getFuelLimit()`


# Walkback pruning
An optimization we can make to prevent pointless movement is nullifying any loops we've made in our movement. For example, if we move 2 steps forwards, and 1 step back, we dont need to rewind by moving forwards first, since we've moved into a position we've already visited.

Therefore, after every movement, we check if we've already visited this position. If we have, we can remove all positions after this one.
Otherwise, we will push the position to the step list.

Even if the rotations don't match, steps can be added to the walkback to fix the rotation difference.

### A note on performance
As detailed in [lua notes](../lua/lua_notes.md), tables are implemented as hashmaps, thus checking if a position is already contained is fairly cheap.

# Walkback position storage implementation
Walkback positions need to be known in order, and also looked up by position.

To facilitate these lookups (and keep them fast), each list of elements needs to be split into 3 parts.

Since we want to check positions regardless of their rotation, we separate rotation data into its own dedicated table. Rotations are stored as a key-value pair, such that to look up a position's rotation, you need to know the index of the position.
```lua
-- indexed with the move's index.
rotation = Vec<direction>
indexes[number]
```

Similarly, we want to be able to look up the index of a move based on its position, thus we have another table for that.
```lua
-- indexed with positions
indexes = Vec<number>
indexes[position]
```

And finally, we need to be able to go from an index into a position.
```lua
-- Indexed by just normal numbers, the most recent move is at the end of the array.
positions = Vec<position>
positions[number]
```

These are all bundled together into the `current_walk` table.
```lua
current_walk = {
    rotation,
    indexes,
    positions
}
```

Additionally, we want to be able to look at old positions that aren't in the current walkback, so we keep a FILO buffer of all of the positions we've seen for ~~the last 1024 positions~~. This does not include rotation information, since it is meant to be used purely for checking if we've existed in some spot in the past.

~~However, we do still need to know the ordering of the positions, since we want to remove the oldest onces, thus we are forced to additionally use a second array to keep track of the elements.~~

Note: there is currently no limit on how big this buffer can get, which yes, this can use infinite ram, but in practice this should get cleared out pretty often. If memory usage becomes a problem, we can fix it later.

```lua
-- ~~This contains the last 1024 seen positions.~~
-- This is implemented as a K,V hashmap of Position, Bool
-- The boolean is always set to `true` to make `nil` checks easier.
-- Thus this is in all practical sense a hashset.
all_seen_positions = {}
```

When all tasks have

# Walkback documented blocks storage implementation
To prevent needing to write a custom block deserializer in Lua (I would rather die) we will simply store the entire output for each block we've seen in a hashmap, where the key is the position of the block, and the value is whatever `turtle.inspect()` returned.

This is also an unlimited size for the same reason as position storage.

```lua
-- This is implemented as a K,V hashmap of Position, Table
all_seen_blocks = {}
```

# JSON export format
When a turtle has finished all of its tasks (or when the control computer directly requests it), turtles will convert all of their internal walkback data into json and send it to the control computer. It is the job of the Rust code to make sense of the resulting json, since any more formatting on the lua end would be too slow.

All of the internal walkback data is assembled into a table with the sub tables in it, then this data is ran through `textutils.serializeJSON()`
```lua
json_me = {
    all_seen_positions,
    all_seen_blocks,
    current_walk
}
```