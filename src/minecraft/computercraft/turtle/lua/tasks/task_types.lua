--- TurtleTask is the type used to store basic / common task information. Tasks
--- take in this type with an inner `config` field used for more fine-grained
--- data about how the task should be performed.
---
--- walkback: It is safe to push, pop, and do whatever you want to this walkback,
--- since before you get a reference to it, the OS has already made a local copy,
--- and has completely cleared the walkback's state fresh for the task.
--- However, if the task config requires you to return to the starting position,
--- you must either return there manually yourself at the end of the task, or
--- ensure that the walkback chain you have created will take the turtle back to
--- where the task started.
---
--- start_time: This is set when the task is created, and is a epoch("utc")
---
--- last_subtask_result: This will store the the result of the most recent
--- subtask after returning from a sub-task, however, the value contained here will
--- immediately be stripped back off of the TurtleTask via spawnSubTask, since
--- the callers of spawnSubTask get that task data as a result. Thus, this field
--- should almost always be nil.
---
--- @class TurtleTask
--- @field start_time number -- Starting timestamp.
--- @field walkback WalkbackSelf -- A reference to the global walkback.
--- @field start_position CoordPosition -- A copy (NOT REFERENCE) to where this task was started.
--- @field start_facing CardinalDirection -- What direction was being faced when the task started.
--- @field task_thread thread -- The thread that this task runs on.
--- @field definition TaskDefinition -- The inner definition for the task.
--- @field is_sub_task boolean -- Wether or not this task was spawned via another task.
--- @field last_subtask_result TaskCompletion|TaskFailure|nil -- See notes above.

--- Partial task configs only hold enough information for the definition of the
--- task, but do not contain the inner information that must be set up by
--- MeshOS before the task starts.
---
--- A final TaskConfig is wrapped around this later.
--- @class TaskDefinition
--- @field return_to_start boolean -- Wether or not the task needs to end where it started.
--- @field return_to_facing boolean -- Wether or not the task needs to face in the same direction it started in.
--- @field fuel_buffer number -- Target amount of fuel to keep in the turtle. Task fails if task does not self-refuel and fuel falls below this number.
--- @field task_data TaskDataType -- The inner configuration for the specific task.


--- Just a nicer alias for all the different task data.
--- @alias TaskDataType
--- | TreeChopTaskData
--- | RecursiveMinerData
--- | BranchMinerData

--- TaskCompletion is the type returned by tasks when they finish their duties and
--- no-longer need to be resumed.
--- @class TaskCompletion
--- @field result TaskResultData -- Data returned from the task if needed.
--- @field kind "success"

--- TaskFailure is what is returned when a task has done some partial amount of
--- work, but was unable to finish due to some failure.
--- @class TaskFailure
--- @field kind "fail"
--- @field reason TaskFailureReason
--- @field stacktrace string


--- Reasons for task failure
--- @alias TaskFailureReason
--- | "bad config" -- Passed the wrong config type to the task.
--- | "assumptions not met" -- Task was expecting some state, did not get it.
--- | "assertion failed"
--- | "inventory full"
--- | "out of fuel"
--- | "walkback rewind failure"
--- | "sub-task died"

--- The special `none` result type for tasks if they don't need to send any
--- response information. Imagine a task that only spins in a circle as a dumb
--- example.
--- @class NoneResult
--- @field name "none"

--- Data that tasks can return. Each task will have its own return type, but not
--- all tasks return data.
---
--- These data types are defined in their respective task files.
--- @alias TaskResultData
--- | RecursiveMinerResult
--- | BranchMinerResult
--- | NoneResult