# Prelude types
There are a few types that will be frequently re-used, they are defined here.

# How to read this file
Fields of tables are set to a `type` instead of a concrete value, it is implied that it would have an actual value of that type at runtime. The types within the fields may reference other types, which will be surrounded with angled brackets.

Above each type will be a comment showing what kind of type we are mimicking. Enums will also indicate the type contained within the enum, although this should already be obvious.

Enums will list all of their variants.

# MinecraftPosition (position) and MinecraftFacingDirection (facing)
```lua
-- Struct
position = {
    x = number,
    y = number,
    z = number,
    facing = Option<facing>,
}
```
```lua
-- Enum : String
facing = {
    "north",
    "east",
    "south",
    "west",
    "up",
    "down"
}
```

# Tuple `(T, T, ...)`
Tuples are ordered, and their fields are not named. They are simply a combination of any arbitrary type.
```lua
-- Tuple
tuple = {}
tuple[1] = T
tuple[2] = T
-- ...
```
Tuples when referenced as a type are not called tuples, or `tuple<>` or anything of the sort. They are simply refered to with standard parenthesis notation. IE, a tuple with a `String` and a `Bool` in it would be `(String, Bool)`.

Accessing items in tuples is simple, as they are just tables/arrays after all.
See the [lua manual](https://www.lua.org/manual/5.3/manual.html#3.2).

```lua
-- we have a tuple of (String, Bool) named `tuple`
inner_string = tuple[1]
inner_bool = tuple[2]
-- or
inner_string = tuple.1
inner_bool = tuple.2
```

# Yield types
See `context_switch.md`

# Array `Vec<>`
To keep consistent in naming, we refer to growable arrays (since all arrays are growable in lua) as Vec.
```lua
-- Vec<String>
vec = {}
table[1] = "string!"
print(table[1]) -- "string!"
```

# Optional `Option<>`
Since Lua has made the [billion-dollar mistake](https://en.wikipedia.org/wiki/Tony_Hoare) we have to deal with a null type, known in lua as `nil`. When implementing options, they are simply a value of either `nil` or a value. Do note that you should not use `Option<bool>` since we check if a value is `Some()` via casting `nil` to `false`.
```lua
-- Option<String>
option = nil

if option then
    print(option) -- not executed.
end

if not option then
    print("value is nil") -- "value is nil"
end

option = "some"

if option then
    print(option) -- "some"
end

if not option then
    print("value is nil") -- not executed.
end
```