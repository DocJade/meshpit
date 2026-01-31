# Panicking

When we panic, we need to get as much information about the turtle as possible as we die, since we would really prefer to be able to write better error handling for the edge case that you came across.

# Implementation
See [stack overflow](https://stackoverflow.com/questions/2834579/print-all-local-variables-accessible-to-the-current-scope-in-lua)

After obtaining the return type, we should either send this data to the controller computer as soon as possible or store it in the message buffer until we are able to send it.

# Panicking return type
```lua
-- Struct
panic_data = {
    -- A stack trace of where the panic was called.
    stack_trace = string,

    -- Every local variable.
    -- In the format of an array of pairs.
    locals = table,

    -- Every external variable we are referencing. This table has no overlap with locals.
    -- In the format of an array of pairs.
    up_values = table,
}
```