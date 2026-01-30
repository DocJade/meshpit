# refuel_other supertask
Goes and refuels another turtle that is stranded somewhere.

This task is only used on destination turtles that are completely static, as we expect the turtle to be at this location indefinitely as we prepare and deliver fuel for it.

### Sub-tasks
1: Fuel acquisition
- This task is determined by the server, since the fuel gathering method is situational.
- Collected fuel must end up in a known, pre-determined slot.

2: `move_to`
- Go to the turtle we are refueling and face it

3: `insert_item`
- Self explanatory

# Failure modes
- Turtle was not present at the destination position
- Unable to path-find to the turtle.