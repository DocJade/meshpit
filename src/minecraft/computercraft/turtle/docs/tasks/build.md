# build task

# NOTES TODO:
takes in a list of blocks and their positions and builds them

lots of care will have to be taken by the control computer on ordering to ensure that turtles dont trap themselves or others, and that they dont surround a block before they place it.

This will be very complicated. I will figure this out later.


Given:
- Collection of block IDs and positions (schematic)
  - Including `air` and `no_change_solid` (blocks which will not be modified by the build task, but cannot be pathed through)
- Definition of build volume
  - naively: XYZ + Length Width Height of a box
  - including free spaces on the surface of the box where the turtle can enter

Terms:
- `to_change` blocks: not `air`, not `no_change_solid`

Methods:
- count_depth: assigns a depth value to each block in the build volume
    - starting from the free spaces: step into each neighboring block (in the build volume), and increase the current score based on these rules:
      - stepping into `air` is worth 1
      - stepping into `to_change` is worth `k`
      - stepping into `no_change_solid` is worth \<big number? infinity?\>
    - if the block has no score or has a higher score than current, set the block's score to the current score. then step into each neighbor
    - if the block's score is lower than or equal to the current score, ignore & continue
- find_surface: return a collection of `to_change` blocks that can be reached by pathing only through `air`
  - similar impl to `count_depth` 

Then:
- Simulate reverse deconstruction of the build:
  - while `to_change` blocks exist:
    - increment time by 1 frame (seconds or ticks?)
    - if: no blocks in `find_surface`: skip iteration
    - else if: dont want to deploy a turtle this frame (see Note 3): skip iteration
    - run `count_depth` and keep a copy of the result
    - pick a random `to_change` location on the build
    - simulate: (see Note 1)
      - collect the turtle path to reach the location into `work_path`
      - vein mine until inventory full (or other condition, like blocks mined):
        - starting at the location, choosing the neighbor with highest score from `count_depth`
          - neighbor probably should also need to match turtle inventory contents/be able to fit in the inventory
        - "move" the turtle into the position last dug, add the previous position into `work_path`
      - if no blocks available from current position, probably should seek nearest `to_change` (see Note 2)
    - mark the blocks from `work_path` as `no_change_solid` for the next N \<time interval\>
      - 1 second per block in `work_path`? unclear
      - assuming all mined blocks get added to `work_path` as well
    - then after the interval, mark them as `air`
- With the simulation result:
  - Reverse every `work_path`:
    - place instead of dig
    - calculate the time (might need to think about this more)
  - issue each `reversed_work_path` to turtles according to time
  - would probably require some kind of blocking to make sure they dont start too soon, but this should be easy to determine during the simulation phase (see Note 4)

Notes:
1) As written, a simulation run at time T would assume the block state remains as it was at time T for any portions of the build that should be concurrent (T + t_i). There's a mild inefficiency here in this regard. You could reinterpret this implementation in a way that manages "active turtles" that are simulating per frame, and committing their `work_path` to `air` once theyre finished.
2) the specific mining alg influences this by a lot. the core idea is to minimize the scores of `count_depth`, as this should result in an interesting build pattern. 
3) I have a suspicion that allocating a turtle every frame possible (`find_surface` not empty) would lead to unfavorable results, like less interesting building patterns. Partially this has to do with the simulation temporarily blocking the `work_path` of other turtles. My first idea here is to decide the probability of sending a turtle based on the amount currently "active", e.g. no active turtles always chooses to simulate, many active turtles is hesitant to add another. could also scale with the size of `find_surface`
4) there probably should be a distinction between this large build command and a smaller build command turtles receive, where the smaller build runs with these assumptions:
- the turtle will Eventually complete (it may *pause*)
  - essentially, the path might be blocked temporarily by something else, but it is Guaranteed™ to be free later without intervention on the turtle's part
- the turtle can hold all of the building material for the task (no restocking required)