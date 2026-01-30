# dig task

This task takes in two MinecraftPositions that form the volume that should be excavated by the turtle.

Do note that the starting position should be in one of the corners of the volume that was requested to be dug.

This task shares the default deny list with the [mining](./mining.md) task, but can be disabled by setting `ignore_deny_list`. You should almost never ignore the deny list, but the option is there if needed.

This task has a fuel limit, if at any time the following expression is true, the turtle will cancel its mining task.

`max(number of blocks remaining in volume, walkback.cost() * 2) > fuel_level`

# Task behavior
The turtle will make its way to the start position, then decide on a mining pattern. usually going in a zig-zag pattern along one of the faces of the volume to dig.

The turtle will keep track of how many blocks it has mined and how many are remaining, and thus could be capable of returning a progress metric in the future. Currently such a metric does not exist.

Occasionally, the fuel check will be ran, and if that fails, the turtle will return to the start position before ending the task. This cancelation behaviour will also occour if the turtle has an item in every inventory slot, since we don't want to drop any items on the ground.

Otherwise, the turtle will continue to excavate the volume until it has mined the final block, then it will return to the starting position.

# Task data

```lua
local dig_task_data = {
    -- the position that the turtle will start excavating from, and will return to after the task completes.
    start_point = position,

    -- The two corner positions of the volume
    pos1 = position,
    pos2 = position,
}
```

# Failure modes
-- Turtle needs to mine an un-mineable block, wether it be unbreakable, or on the deny list.