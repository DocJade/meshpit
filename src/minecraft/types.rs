// Minecraft related types

// ==
// Minecraft Block
// ==

use std::fmt::Display;

#[derive(Clone, Copy)]
pub enum MinecraftBlock {
    LimeConcrete,
    RedConcrete,
    YellowConcrete,
    Netherrack,
    GoldBlock,
    RedstoneTorch,
    Fire,
    CCComputerNormal,
    CCTurtleNormal,
}

impl Display for MinecraftBlock {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MinecraftBlock::LimeConcrete => write!(f, "minecraft:lime_concrete"),
            MinecraftBlock::RedConcrete => write!(f, "minecraft:red_concrete"),
            MinecraftBlock::YellowConcrete => write!(f, "minecraft:yellow_concrete"),
            MinecraftBlock::CCComputerNormal => write!(f, "computercraft:computer_normal"),
            MinecraftBlock::CCTurtleNormal => write!(f, "computercraft:turtle_normal"),
            MinecraftBlock::Netherrack => write!(f, "minecraft:netherrack"),
            MinecraftBlock::GoldBlock => write!(f, "minecraft:gold_block"),
            MinecraftBlock::RedstoneTorch => write!(f, "minecraft:redstone_torch"),
            MinecraftBlock::Fire => write!(f, "minecraft:fire"),
        }
    }
}

// ==
// Minecraft Position
// ==

#[derive(Clone, Copy)]
pub struct MinecraftPosition {
    pub x: i64,
    pub y: i64,
    pub z: i64,
}

impl MinecraftPosition {
    /// Get the position as a string, used in commands (no commas)
    pub fn as_command_string(&self) -> String {
        format!("{} {} {}", self.x, self.y, self.z)
    }
    /// Offset the position by an amount
    pub fn with_offset(&self, offset: MinecraftPosition) -> MinecraftPosition {
        Self {
            x: self.x + offset.x,
            y: self.y + offset.y,
            z: self.z + offset.z,
        }
    }
}

// ==
// Minecraft Facing Direction
// ==

#[derive(Clone, Copy)]
pub enum MinecraftFacingDirection {
    North,
    East,
    South,
    West,
}

impl Display for MinecraftFacingDirection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MinecraftFacingDirection::North => write!(f, "north"),
            MinecraftFacingDirection::East => write!(f, "east"),
            MinecraftFacingDirection::South => write!(f, "south"),
            MinecraftFacingDirection::West => write!(f, "west"),
        }
    }
}

// ==
// 
// ==