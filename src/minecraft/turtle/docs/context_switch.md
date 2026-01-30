# Switching tasks
Tasks are ran as Lua coroutines. More behavioral detail will be added here when this is implemented.

# Yielding
When you yield from a task, you should send a yield message outwards, unless you are purely yielding to temporarily give the operating system back control to do other things in a long section of task code that does not yield due to a lack of external calls, but this is uncommon.

There are many reasons you may yield, one of which is when you are unable to complete the task you are working on due to some criteria, such as running low on fuel.

It is possible that you will never be handed back control after yielding, which is by design. If the control computer decides to revoke tasks, or needs to reset you for any reason, it will kill the yielding processes.

```lua
-- Struct
yield = {
    -- The reason for yielding, if nil, this is just a basic yield
    -- to give CPU time back to the OS.
    reason = Option<yield_reason>
}

```
```lua
-- Enum
yield_reason = {
    -- You do not have (or predict that you will not have) enough fuel to
    -- finish the current task, and the turtle needs to be re-fueled before
    -- it can resume this task.
    "fuel",

    -- We try not to do this, but sometimes we have errors that we are unable
    -- to recover from for some reason. Thus we have a generic `panic!()` type
    -- failure for this.
    --
    -- Panicking should also provide a table of the entire local state of lua!
    -- See `panicking.md`
    ("panic", table),
}
```


# Resuming after yielding

When a coroutine is resumed after it has yielded, you may possibly get a table back based on the kind of yield you did. Otherwise, you will get `nil` and can safely ignore it.

```lua
-- List of results based on yield types.
-- shown as key, value pairs.

-- "fuel"
-- None -- Your task will only be resumed after the turtle has refueled.

-- "panic"
-- None - Your task will never be resumed.
```