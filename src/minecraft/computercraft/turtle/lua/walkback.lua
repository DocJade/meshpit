-- Walkback! see walkback.md

-- Table that holds the functions, and holds the state of walkback as well.
local walkback = {
    -- The position we are at
    position = {
        x = 0,
        y = 0,
        z = 0,
        facing = "n"
    };

    -- The current walkback chain. An array of positions.
    -- Position 0 is the first step in the chain.
    ---@alias WalkbackChain MinecraftPosition[]
    ---@type WalkbackChain
    walkback_chain = {
        
    };

    -- Hashset of all of the positions we've seen so far
    -- Implemented as:
    -- key: minecraft_position (with facing ignored by making it nil)
    -- value: Returns the index into the walkback_chain where this position lives.
    ---@alias SeenPositions table<MinecraftPosition, number>
    ---@type SeenPositions
    seen_positions = {};

    -- This is an internal table used to store internal functions we need to perform
    -- the outer functions, but want to hide behind another `.` so they dont show up in the
    -- exported list. --TODO: can you hide these another way?
    internal = {}
}

-- ========================
-- Type definitions
-- ========================

---@alias FacingDirection "n" | "e" | "s" | "w"
-- enum facing_direction = {
--     "n",
--     "e",
--     "s",
--     "w",
-- };

-- question marks on fields mark them as optional.
---@alias MinecraftPosition {x: number, y: number, z: number, facing: FacingDirection?} 
---@type MinecraftPosition
-- -- A position.
-- struct minecraft_position = {
--     x = 0,
--     y = 0,
--     z = 0,
--     facing = facing_direction.NORTH
-- };





-- ========================
-- Methods
-- ========================

-- ============
-- New methods
-- ============

-- ======
-- Initialization
-- ======

--- Sets up walkback for the first time. Should only be called once!
--- @param x number X position
--- @param y number Y position
--- @param z number Z position
--- @param facing FacingDirection Facing direction
--- @return nil
function walkback.setup(self, x, y, z, facing)
    self.position.x = x
    self.position.y = y
    self.position.z = z
    self.position.facing = facing
end

-- ======
-- Rewind related
-- ======

function walkback.mark() end
function walkback.rewind() end
function walkback.step_back() end
function walkback.previous() end
function walkback.cost() end
function walkback.pop() end
function walkback.push() end
function walkback.pos_query() end
function walkback.hard_reset() end
function walkback.data_json() end

-- ======
-- Block data related
-- ======

function walkback.block_query() end

-- ============
-- Movement functions
-- ============
-- These are not scanning movements, they are meant to be fast.
-- Call these whenever you know exactly where you are going.
-- But remember, the more we scan, the more we learn!

function walkback.forward() end
function walkback.back() end
function walkback.up() end
function walkback.down() end
function walkback.turnLeft() end
function walkback.turnRight() end

-- ======
-- New methods
-- ======

function walkback.forward_scan() end
function walkback.back_scan() end
function walkback.up_scan() end
function walkback.down_scan() end

-- ============
-- Inventory functions
-- ============

function walkback.drop() end
function walkback.dropUp() end
function walkback.dropDown() end
function walkback.select() end
function walkback.getItemCount() end
function walkback.getItemSpace() end
function walkback.suck() end
function walkback.suckUp() end
function walkback.suckDown() end
function walkback.compareTo() end
function walkback.transferTo() end
function walkback.getSelectedSlot() end
function walkback.getItemDetail() end

-- ============
-- Environment detection
-- ============
-- these should update our internal state. We can at least mark it as solid.

function walkback.detect() end
function walkback.detectUp() end
function walkback.detectDown() end

-- ============
-- Block comparison
-- ============

function walkback.compare() end
function walkback.compareUp() end
function walkback.compareDown() end

-- ============
-- Block inspection
-- ============
-- these should update our internal state.

function walkback.inspect() end
function walkback.inspectUp() end
function walkback.inspectDown() end

-- ============
-- Mining
-- ============
-- these should update our internal state.

function walkback.dig() end
function walkback.digUp() end
function walkback.digDown() end

-- ============
-- Placing
-- ============
-- these should update our internal state.

function walkback.place() end
function walkback.placeUp() end
function walkback.placeDown() end

-- ============
-- Equipment
-- ============

function walkback.equipLeft() end
function walkback.equipRight() end
function walkback.getEquippedLeft() end
function walkback.getEquippedRight() end

-- ============
-- Crafting
-- ============

function walkback.craft() end

-- ============
-- Attacking
-- ============

function walkback.attack() end
function walkback.attackUp() end
function walkback.attackDown() end

-- ============
-- Attacking
-- ============

function walkback.getFuelLevel() end
function walkback.refuel() end
function walkback.getFuelLimit() end

-- ========================
-- Walkback pruning
-- ========================

function walkback.internal.post_move() end



-- ========================
-- All done!
-- ========================

-- Return walkback so methods can be called on it.
return walkback