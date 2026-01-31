# Task
Turtles are able to perform pre-defined tasks.

To reduce pointless fields within the task table, there is a sub-table of `task_data` that holds more specialized data for each task. You can see these inner tables in the `./tasks` folder.

# Task data format
```lua
local task = {
    -- The UUID of this task, used by the Rust server to keep track
    -- of things.
    uuid = "4a79955e-2152-4639-8ac3-536e48a11461",

    -- For tracking purposes (or when being used in Supertasks) we
    -- will take note of if a task is finished or not. We do not have
    -- a state for a task being "in progress".
    task_finished = bool,

    -- The name of the task to be performed. Refers to the name of the lua file to run.
    -- In this case, `/task/implementations/move_to.lua()
    task_name = "move_to",

    -- Data specific to this type of task. See the various TaskData implementations.
    task_data = _any task data type_,

    -- The priority of this task. Ranges 0.0..=1.0.
    -- Tasks with a priority of 1 will always run immediately, and supersede any other task.
    -- Tasks with equal priority are done in the order that they were added.
    priority = 0.5;
}
```