# craft task
We assume we already have all of the items in our inventory to craft the requested item, and that we already have a crafting table equipped in one of our equipment slots. The control computer should have already guaranteed this for us.

If there are more items in our inventory than are required for this crafting operation, this task also assumes we have a chest in some slot of our inventory, since we need to be able to clear out any items that are irrelevant for this craft.

Thus, the crafting task is very simple, we will move all un-needed items for this craft into a chest if required, then move all of the items required from this craft into the edges of the inventory, outside of the 3x3 grid. Then we move the items into their grid positions according to the amounts specified in the provided recipe.

# Task data

```lua
-- using prelude types!
local craft_task_data = {
    -- The crafting recipe to execute is given to the turtle as an array of items,
    -- corresponding to the 9 inventory slots used for crafting.
    recipe = [Option<item>; 9]

    -- How many logs to gather. If this is set to zero, the turtle
    -- shall chop trees forever.
    goal = number,

    -- Optionally, the turtle can be told to stop gathering wood after a certain in-game time has passed.
    -- This is expressed in a number of in-game milliseconds since the world was created.
    -- See https://tweaked.cc/module/os.html#v:epoch
    stop_time = Option<number>
}
```
The item representation:
```lua
item = {
    name = string,
    count = number
}
```

# Failure modes.
- There is not enough space to retrieve all of our items after crafting new ones.
- Crafting results in more than 16 slots worth of items
- - If this happens, all of the excess items are dropped on the floor.