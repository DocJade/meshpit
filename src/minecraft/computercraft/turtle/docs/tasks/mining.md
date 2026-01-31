# mining task
Mining is done in a very basic fashion.

This task come with a list of block names to mine. Any blocks that match this list will be mined thouroghly (see Mining pattern), otherwise they will be ignored. But do note that artificially restricting this list to a single ore that you want (such as diamonds) means the turtle will completely ignore mining other ores/blocks.

There is additionally a default deny list inside of the task to ignore important or notable blocks (think spawners or chests), but this deny list can be superseded by explicitly adding the item to the allow list.

When given a starting position that is not at the same Y level as the y level to mine at, the turtle will go to that position, then mine straight downwards until it hits that chosen y level, leaving a hole in the ground.

A bounding box is also provided for this task to ensure that turtles do not mine where they shouldn't, and this can also be used by the control computer to split turtles up into distinct areas to avoid collisions.

When a turtle is done mining (due to running out of fuel or being full of items), the turtle will return to the starting position before moving onto the next task.

There is no time-out on this task, since eventually the turtle will not be able to hold any new kinds of items due to its inventory being full, or the turtle will run low on fuel.

The fuel cutoff for this task is checked with the following expression. If this expression returns true, the mining task is ended.

`walkback.cost() > fuel_level / 2`

# Mining pattern
From their start position (at the correct y level) the turtle will turn to face the direction that gives the most distance between it and the edge of the bounding box of the task. The turtle will then mine forwards and move forwards repeatedly, scanning the surrounding blocks at each step.

When a block on the whitelist is seen, the turtle will write that into its mining stack.

Before every movement, we check if there is anything in our mining stack. If there is a block in there, we pop it off of the top of the stack, mine it, and move into the space it occupied to scan all of the surrounding blocks.

Since ore veins tend to be quite "blobby", marking and mining blocks one by one tends to find almost the entire vein. This does not check diagonally however, but this is good enough for most cases.

If the block on the top of the stack is not directly adjacent to our position, we rewind our position by a single step backwards with `walkback.step_back()`. If the block still is not adjacent, then we will check the walkback list to see if a position next (all sides of the block) to the target block exists. If it does not, then that means at some point the walkback path crossed itself and trimmed off the path to that block. So the turtle will have to directly path to the block instead.

If we are unable to reach the block via rewinding, the turtle will save the walkback state with `.pop()`, `.mark()` a new walkback, then start mining directly twoards the the target block until it has been mined. After mining the target block, the turtle will `.rewind()` and `.push()` the old walkback back into place, before continuing with the normal main loop.

If we get next to a block that we want to mine and it is no longer there, that's fine, we can just ignore it and move on.

# Task data
```lua
local mining_task_data = {
    -- The position to start mining from,
    start_position = position,

    -- What Y level to mine at
    y_level = number,

    -- The two corner positions of the volume that bounds the mining operation.
    -- If a turtle attempts to move or mine outside of this range, walkback will cancel the action, unless the turtle
    -- is already outside of the bounding box, and is attempting to move into it.
    pos1 = position,
    pos2 = position,
}
```

# Failure modes
- Unknown. Might not have one.