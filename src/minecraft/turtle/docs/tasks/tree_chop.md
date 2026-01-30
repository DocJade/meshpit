# tree_chop task
Tree chop is obviously a task about chopping trees, but this task assumes a few things before it runs:
- The position we start the task at has a tree, or sapling in front of us
- The tree / sapling that will grow in front of us is limited in height by a block to prevent large trees with branches.

# Task data

```lua
-- using prelude types!
local tree_chop_task_data = {
    -- There is no destination position, as we are assuming that
    -- we have already been put in the correct position.

    -- How many logs to gather. If this is set to zero, the turtle
    -- shall chop trees forever.
    goal = number,

    -- Optionally, the turtle can be told to stop gathering wood after a certain in-game time has passed.
    -- This is expressed in a number of in-game milliseconds since the world was created.
    -- See https://tweaked.cc/module/os.html#v:epoch
    stop_time = Option<number>
}
```

# Failure modes
- The turtle has ran out of inventory space to hold the logs.
- There is no sapling to place.

# Notes
According to the minecraft wiki, breaking leaves has the same chance of dropping a sapling as waiting for the leaves to decay.