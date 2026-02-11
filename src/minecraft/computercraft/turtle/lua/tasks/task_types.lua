--- TaskConfig is the type used to store basic / common task information. Tasks
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
--- @class TaskConfig
--- @field start_time number -- Starting timestamp.
--- @field walkback WalkbackSelf -- A reference to the global walkback.
--- @field return_to_start boolean -- Wether or not the task needs to end where it started.
--- @field return_to_facing boolean -- Wether or not the task needs to face in the same direction it started in.
--- @field start_position CoordPosition -- A copy (NOT REFERENCE) to where this task was started.
--- @field start_facing CoordPosition -- What direction was being faced when the task started.
--- @field fuel_buffer number -- Target amount of fuel to keep in the turtle. Task fails if task does not self-refuel and fuel falls below this number.
--- @field task_data TaskDataType -- The inner configuration for the specific task.


--- Just a nicer alias for all the different task data.
--- @alias TaskDataType
--- | TreeChopTaskData



--- TaskCompletion is the type returned by tasks when they finish their duties and
--- no-longer need to be resumed.
--- @class TaskCompletion
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