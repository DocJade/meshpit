# Table facts
Sources:
- https://stackoverflow.com/questions/29928379/how-are-lua-tables-handled-in-memory
- Word of mouth, _CodeGreen

Tables are implemented as partially a hashmap and an array, which part of the table is used depends on the operation. For example, treating a lua table as an array with direct indexing uses the underlying array, and thus is very cheap. Do note that this only works on positive integer keys starting at 1, and this behavior is not guaranteed (For example, a brand new table can have the 10 millionth index set to a value, but that will use the hash side of the table instead of allocating a million sized array.). In contrast, indexing with a more complicated type, IE anything that is not an integer, the table will look and store that information in the hash side of the table.

You can also use tables as keys into hashmaps, thus any type we create in lua can be used as a key to another table.
```lua
table = {}
position = { x = 1, y = 2, z = 3, facing = "north" }
block = "air"
table[position] = block

print(table[position]) -- "air"
print(table[1]) -- nil
```

However, you cannot index tables with types passed by reference.

# References
Sources:
- Word of mouth, _CodeGreen

All simply types are by value, complicated stuff (tables, functions, etc) are by reference.

How can you tell if something is a reference without a marker like Rust's `&`?
"you just gotta know" - _CodeGreen

# Table indexing
The [-1]st index of a table is not the last index of the table. IE, in a table with 5 values, table[5] != table[-1].
Instead, negative numbers are treated as keys to the hashmap part of the table.

# Randomness
Lua by default seeds its pseudorandom number generator once. I do not know if CC:Tweaked randomizes each turtle with a unique seed, but just in case, if you need more random number (for things such as network packets), you should re-seed the RNG with values specific to that turtle, such as its position, ID, and the current time.

# Yielding
Through various benchmarks, I found that `os.queueEvent` followed by `coroutine.yield` were the fastest way to yield. Moreover they're pretty much the ONLY way to yield, as the other functions I found that cause yielding are turtle related, and can only happen once per tick.

Thus the fastest way to yield is:
```lua
local q = _G.os.queueEvent
local y = _G.coroutine.yield
local s = ""
q(s)
y()
```

But unless your loop is extremely tight, the overhead of pulling globals into locals really doesn't matter, nor does doing coroutine yielding versus pulling events.

However, `coroutine.yield` can only be used standalone if this is not the main thread, as it will completely yield control back to the OS thread, which is preferred. Thus you should only need to call `coroutine.yield()`. But, this cannot be called when outside of a coroutine, or it will block forever (or until some random event happens, which is not preferred.). Therefore simply calling `os.queueEvent("^")` then `os.pullEvent("^")` is plenty fast.

***ONLY*** use coroutine.yield directly when you want to pass something back to the OS, or when yielding occasionally to the OS for general tasks.

Benchmark:
```lua
loop_count = 10000000
print("Running " .. loop_count .. " times")
local q = _G.os.queueEvent
local y = _G.coroutine.yield
local s = ""
the_start = os.epoch("utc")
for _ = 1, loop_count do
	q(s)
	y()
end
the_end = os.epoch("utc")
print("started")
print(the_start)
print("stopped")
print(the_end)
print("duration")
duration = the_end - the_start
print(duration)
print("YPS")
yps = loop_count / (duration / 1000.0)
print(yps)

-- Tested with 1,000 - 10,000,000 yields

-- Things that do yield:
-- Event yeilding
-- -- local _ = os.queueEvent("^"), local _ = os.pullEvent("^") - ~140,000
-- -- os.queueEvent("^"), os.pullEvent("^") - ~140,000 (slightly faster on average)
-- -- bind the os calls to locals instead - ~145,000
-- -- ditto, queue an empty string and use no filter on pull - ~147,000
-- -- use _G.os instead of os -- ~147,000 (no practical difference?)
-- -- use _G.coroutine.yield() instead of pullEvent -- ~160,000
-- turtle.craft(0) - ~20 -- Requires crafting table
-- turtle.select(1) - ~20
-- turtle.compareTo(1) - ~20
-- turtle.attack() - ~20
-- (seems all of the world related turtle calls are limited to once per tick)


-- Things that do not yield:
-- os.cancelAlarm()
-- os.cancelTimer()
-- os.getComputerID() 
-- os.getComputerLabel()
-- os.setComputerLabel() -- even with a string.
-- os.sleep() -- Would eat events. Do not use.
-- os.clock()
-- os.time() -- none of the locales either
-- os.day()
-- os.epoch()
-- os.date()
-- function a()end, parallel.waitForAny(a)
-- peripheral.find("dummy")
-- peripheral.getNames()
-- coroutine.yield() -- Breaks after 1 yield
-- commands.execAsync("")
-- fs.isDriveRoot("")
-- fs.getDrive("")
-- fs.getFreeSpace("")
-- io.flush()
-- redstone.getOutput("top")
-- redstone.getInput("top")
-- redstone.setAnalogOutput("top", redstone.getAnalogOutput("top"))
-- settings.undefine("glorp")
-- shell.aliases()
-- term.native()
-- textutils.serialize()
-- textutils.serializeJSON("")
-- turtle.getSelectedSlot()
-- turtle.getFuelLevel()
```