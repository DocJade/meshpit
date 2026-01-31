# insert_item task
This task assumes that directly in front of the turtle is some inventory that can have items `turtle.drop()`-ed into it.

This task only checks that some block exists in front of the turtle, not for a specific type of block.

# Task data

```lua
-- using prelude types!
local insert_item_task_data = {
    -- There is no destination position, as we are assuming that
    -- we have already been put in the correct position.

    -- Which slot of the turtle's inventory should be `drop()`-ed into
    -- the inventory.
    slot = number,

    -- How many of the item in that slot should be put `drop()`-ed in.
    -- If none, the entire slot should be put in.
    count = Option<number>
}
```

# Failure modes
- The turtle has no block in front of it, thus it would be impossible to `drop()` an item into it.
- The slot the turtle is trying to `drop()` from is empty.
- The slot the turtle is trying to `drop()` has less items than requested.
- The destination block is already full of items.