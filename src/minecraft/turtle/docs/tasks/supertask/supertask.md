# Supertask
Some tasks are actually more easily represented as a group of sub-tasks. These task groups are referred to as Supertasks.

Supertasks are a collection of sub-tasks that are ran in a pre-defined order. A good example of a Supertask is the `refuel_other` Supertask. Refueling another turtle is an important task, and could have its own implementation completely, however, it makes more sense to compose it out of other pre-existing tasks.

Supertasks also don't necessarily need to be pre-defined, and thus you can use Supertasks to more generically assign a large set of tasks to a single turtle.

Since Supertasks let us delegate a more complex task to a turtle, it also makes it easier to re-assign a complicated task to a different turtle if the turtle currently performing the tasks becomes sub-optimal for any reason. Additionally, it is also possible to tell turtles to skip a step in a Supertask. This can be desirable in situations where we've delegated multiple long tasks to a single turtle (mining expeditions, for example), but now no longer need a single turtle to perform this task, and can split the workload up amongst multiple turtles.

# Task data format
```lua
-- Example move_to task
local supertask = {
    -- The UUID of this supertask, used by the Rust server to keep track
    -- of things.
    -- Do note that the sub-tasks also still have UUID's attached to them, so the Rust server is able
    -- to keep track of the progress of the supertask.
    uuid = "4a79955e-2152-4639-8ac3-536e48a11461",

    -- The name of the supertask being performed. Unlike normal tasks, these tasks do not have a
    -- dedicated implementation file, instead this list of tasks is fed to the turtle directly.
    task_name = "move_to",

    -- The list of tasks to perform. Tasks are in order, from first to last.
    sub_tasks = {task, task, ...}

    -- The priority of this supertask. Ranges 0.0..=1.0.
    -- Normal priority rules apply, but this value is the priority of the entire supertask, and
    -- thus its sub-tasks's priorities are overruled by this value.
    priority = 0.5;
}
```