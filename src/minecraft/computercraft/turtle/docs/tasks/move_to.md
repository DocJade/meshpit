# move_to task
Very simple task that instructs the turtle to navigate to an end position.

This task is very simple by design, but additionally packs a few extra features to help turtles on the way to their destination.

For example, the command computer can supply a list of a few known "good" waypoints along the path to the destination for the turtle to aim for, which will make path-finding easier.

# Path-finding evaluation
Due to turtles having low-information about the world around them, normal path-finding algorithms such as A* or Dijkstra will not work. Instead we have a custom solution that works well in low-information environments.

The core of the algorithm is minimizing taxicab distance via preferring to move on the axis that has the greatest delta.

Basically, say we have the following situation:
```
G Goal | T Turtle
   X
G......
.......
.......
.......
.......
....... Y
.......
.......
.......
.......
......T
```

When evaluating a move, the turtle will pick a move that will move it along the axis that is the longest from the goal. In this case, that would be the Y axis. Thus the turtle would move upwards in our diagram.

However, if we always picked the longest axis, this would result in zig-zagging while approaching the goal once the axises are of equal length.

```
G|.....
.-|....
..-|...
...-|..
....-|.
.....-|
......T
```

This wastes time, since it takes the same amount of time for a turtle to rotate 90 degrees versus. Thus if we are already facing a direction, we will just prefer to continue to head in that direction. Do note that this restriction does not apply to vertical movement, since that can be done at any time.

```
started facing up
G-----|
......|
......|
......|
......|
......T
```

### Object avoidance
When there is something in the path of the turtle, we can no-longer continue to travel in the direction we were already facing. We will now start doing object avoidance by ranking paths to take.

Say we have the following situation.
```
facing up
G......
.......
..###..
...T...
.......
```

In this situation, since we can no longer move in our preferred direction (forward), we have to rank all of the movements we can make.

Scores are more positive if they are more preferred.

We obviously want to prioritize moving towards the goal and not away from it, so moves are scored based on the following criteria:
- On the longest axis:
- - Decreasing the axises length: +3
- - Increasing the axises length: -3
- On the second longest axis:
- - Decreasing the axises length: +2
- - Increasing the axises length: -2
- On the shortest axis:
- - Decreasing the axises length: +1
- - Increasing the axises length: -1
- Turning
- - Move requires turning: -1 for every required turn
- Open space
- - Cannot move into block: -100 (Should not even be saved)
- - We do not break blocks when path-finding.
- Vertical
- - Move is vertical: +1
- - There is never a turning penalty to moving vertically, so it is worth exploring these options first. This also tends to help in situations where you are "walking" up a hill.

```
facing up
G  .  .  .  .  .  .
.  .  .  .  .  .  .
.  .  #  #  #  .  .
.  .  1  T  -3 .  .
.  .  .  -4 .  .  .
```


After we've ranked all of our options, we add them to the stack in reverse order of preference, such that our favorite option is on top.

(Do note that we will not store steps as just directions to move, but we do here for ease of explanation.)
```
down, right, left
```


After we've made a move, we rank the new options, and add those to the stack.

```
facing left
G  .  .  .  .  .  .
.  .  .  .  .  .  .
.  .  #  #  #  .  .
.  1  T  -4 .  .  .
.  .  -4 .  .  .  .
```
```
down, right, right, down, left
```

And so on. It would not make sense to keep track of all of the possible path positions when we have been traveling in our preferred direction many times in a row (imagine a turtle in a plains biome that just stepped around a single tree's trunk), so after some limit of steps of being able to pick our favorite option, we stop doing object avoidance (this is also our maximum search depth), discard all of our stack, and go back to the normal taxicab distance based movement priority.

But, you may have noticed that theoretically, you could end up in a situation where you move back and worth between two paths over and over!

Luckily we also keep track of every block we have visited (we do this anyways when we move, since we want to report that the block is air back to the controller computer in the future), and thus can ban exploring blocks when doing Object avoidance. The only exception to this rule is when there are only already attempted positions to check (such as being stuck in a 1x1 hole, or being stuck in a room). Since these blocks are stored separately, clearing our stack is fine.

If we hack checked every possible space within our depth limit and still not found a clear path, we will bail the move_to task completely.

On top of our depth limit, we also have an additional hard fuel limit. When the hard fuel limit is hit, we bail the task. This fuel limit is expressed as `taxicab distance to goal > fuel level / 2`. Since we want to have a fuel reserve for other movement after failing the task.

### Waypoints
When evaluating movement, if there are waypoints available, we pick the next waypoint instead of using the true final goal. Once a waypoint is reached, it will pop it off of the waypoint list.

Waypoints are generated server-side, which means the server has a lot more information about that world to do path-finding with, thus the sever should provide us with clear or mostly-clear.

Example:
```
G......
######.
..W....
...####
.......
..W...T
```
```
G-----|
######|
..W----
..|####
..|....
..W---T
```

### Bailing
When we fail to find a valid path, due to either running low on fuel or exhausting our search space, we have to give up on the move_to task, and all of the subsequent tasks after it, since some tasks are tied to arriving at a specific position.

Thus we call out to the controller computer to cancel our task. If we are unable to communicate with the controller unit, we will re-wind our movement to the last position we knew that we could reach the controller from. See `walkback.md`.

### Stack data
While we are exploring the search space, we have a couple local variables to keep track of.

Stacks are implemented by pushing/popping with lua's insert/remove functions. See the [lua manual](https://www.lua.org/pil/19.2.html).

Stacks
- Positions to check: `check`
- Rewind positions: `back`
- Previously checked positions: ( we do not store these ourselves, we will reach out to `walkback` when we need to check if a position has already been visited.)

When we discover new positions, we push them to the `check` stack, unless the current `back` stack is greater than or equal to our maximum search depth. When searching a new position, we pop the position to check from `check` and push it to `back`.

If we've hit the search depth limit (ie, depth >= limit), we pop from back twice, the first pop removes our current position, and the second pop gives us the spot we need to move back to. Even if we've rotated since the current position and the previous one, we can deduce a rotation direction to end back up at the previous block in at most 1 rotation, since we can always move backwards into spots we've already been in, since we know they are clear.

If we move 

Positions are pushed onto the stack in the following format:
```lua
-- format is the same on both stacks.
local stack = {}
table.insert(stack, position)
```

# Task data

```lua
local move_to_task_data = {
    -- Target position to move to. Includes facing direction.
    goal = position,

    -- Waypoints that we will travel to on the way to the goal position.
    -- This table will not always exist, since not all paths require waypoints.
    -- Waypoints in this table are sorted first to last, but also have backup ID's to check
    -- just in case.
    waypoints = Option<[position]>
}

waypoint = {
    -- The index of this waypoint. Index `1` is the first
    -- waypoint to travel to on the way to a destination.
    index = number,
    goal = position
}
```

# Failure modes
- The turtle exhausts its search space.
- Rewind failures.
- The turtle does not have enough fuel to continue the search.