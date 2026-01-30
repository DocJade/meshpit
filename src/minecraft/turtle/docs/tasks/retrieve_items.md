# retrieve_items task
Retrieving items is complicated, luckily we can depend on the control computer to handle the hard part of finding the items we need us.

This task is extremely generic, since it is assumed that the computer will set up other pre-requisite tasks to put the turtle in the state it needs to be able to retrieve an item from somewhere.

There are 2 cases:
- We are obtaining an item from some form of storage
- The item will magically appear in our inventory

In the first case, the computer will have already positioned us in such a way that the container in front of us will have the item we need, and all we need to do is search for the item inside of the container, and take it.

In the second case, we just need to wait until that item shows up in our inventory.

Very simple!

# Task data

```lua
-- using prelude types!
local retrieve_items_task_data = {
    -- Are we just waiting for the item to magically appear in our inventory?
    wait = bool,

    -- The following fields are `nil` if `wait` is true.

    -- What item do we want?
    item_name = string,

    -- How many of this item do we want?
    item_count = number
}
```

# Failure modes
- We are waiting for an item to arrive in our inventory, but it never arrives.
- The container in front of us does not contain the items we need.
- There is no container in front of us.
- There is no space in our inventory for new items.