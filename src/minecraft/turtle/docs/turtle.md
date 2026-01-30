# Turtle
We want our turtles to be independent of the controller computer as much as possible. Thus Turtles are driven with a task-based system where they are free to work on their tasks in the order that they see fit, completely without external intervention. It's a swarm of Turtles, not a single computer driving them all manually, that would defeat the point.

### Making a new turtle
Crafting a turtle requires:
- 7 iron ingots
	- Smelting an item takes 10 seconds (or fuel) per item, thus we will need at least 70 seconds worth of fuel. This slightly less than 1 coal at 80 seconds.
- 1 chest
	- 2 logs
- 1 Computer (as a crafting ingredient)
	- 7 stone blocks
		- Must be smelted from 7 cobble, thus 70 seconds of fuel.
	- 1 Redstone dust
	- 1 glass pane
		- You will need 6 sand for this, 60 seconds of fuel.
- A crafting table is also required to be equipped on the turtle to turn it into a crafting turtle to be able to, well, craft.

Additionally, you will need a disk drive and 1 Floppy, since we need the new turtle to grab a startup program. But these could possibly be shared.

- Disk Drive
    - 7 stone
    - 2 redstone
- Floppy disk
    - 1 paper
    - 1 redstone



### Init process
When Turtles are initially created by other Turtles, they will be off, and have no startup script. Luckily turtles will automatically wrap any nearby disk drives to check for a `startup.lua` file to execute.

This startup file should be able to detect if the file is not on the turtle itself, and if it is not, it should copy itself to the turtle.

The init lua file should contain enough networking to let us reach out to the controller computer for all of the other files.
- These other files can have updates pushed to them remotely, thus we don't want to keep stale copies on the floppy disk.

After the turtle has obtained all of its information to start running properly, it will call its [main function](./main.md) and wait to be assigned [tasks](task.md).