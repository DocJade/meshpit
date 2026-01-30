notes: not a full spec yet

Turtles can fly into the sky to figure out their Y coordinate, but this does not work in the nether, so turtles in other dimensions will have to determine their Y position in other ways.
- Is the end platform at a set height?
- Is the lava ocean at a set height that we can check for? would require us to find a lava ocean first...
- - Is the bedrock mess at the top of the world at a constant Y level? you could just fly up until you hit bedrock, then scan to confirm that there is no bedrock to your sides, and that would be the bottom of that messy bedrock.

Every time a turtle moves, it should track that movement internally with a set of its internal GPS coordinate state. So even in the case that we have no GPS connection, a turtle is still able to navigate.

Turtles are be able to re-orient themselves directionally with any block that has a facing direction, such as signs or pistons. Placing and inspecting a directional block will always give a turtle enough information to re-orient.

Turtles should periodically (configurable by the control computer) update their position if it is invalid.

Turtles should keep track of the last time they synced up their position with GPS.

If a turtle reaches out for a update on GPS position and the returned position does not match the turtles internal tracked position, double check, move a tile in some direction and re-check GPS again. If the delta changes, its an issue with GPS, otherwise if the offset is constant, the turtles position has become de-synced from reality. All data since the last time the turtle successfully synced their position is now invalid and shall be discarded, and the controller computer should be informed that a GPS de-sync occurred when possible.

For some tasks, a GPS de-sync is a big issue, such as when a turtle is in the process of path-finding, as all of the positions it previously checked are no-longer known. Thus it may be required for the turtle to completely cancel the task they were performing due to this de-sync.

Turtles should be able to determine their GPS position relative to other turtles near them regardless to if they can reach out to an official GPS source, but the turtle does still want to occasionally know with fact their authoritative position. Thus other turtles contributing to triangulating its own position should have less authority the longer they themselves have not been updated from an authoritative source. This will allow turtles in groups to still work outside of effective GPS coverage, but still prevent entire groups of turtles of getting positional drift.

However, when out of authoritative range, turtles must triangulate with enough other turtles to do a majority/consensus vote. This vote must consist of an odd number of turtles to break ties, and must have at least 3 turtles to make consensus. If at any time a consensus is not able to be reached due to irreconcilable disagreement (Such as 3 turtles out of a group of 5 disagreeing on where they are positioned), all of the turtles are to invalidate their positions.

If any turtle working as an isolated / non-authoritative gps source is accused by consensus of having a drifted position, it is to immediately invalidate its position

Turtles cannot send any position related data back to the control computer if they have an invalidated or stale position until they are able to verify their position with an authoritative source. This prevents turtles from returning world data, such as block positions, that are offset from reality.