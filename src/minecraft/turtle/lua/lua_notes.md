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