// Minecraft related types

// ==
// Minecraft Position
// ==

use std::fmt::Display;

#[derive(Clone, Copy)]
/// The world position of something in Minecraft.
///
/// This may contain a facing direction, but is not mandatory.
pub struct MinecraftPosition {
    pub x: i64,
    pub y: i64,
    pub z: i64,
    pub facing: Option<MinecraftFacingDirection>,
}

impl MinecraftPosition {
    /// Get the position as a string, used in commands (no commas)
    pub fn as_command_string(&self) -> String {
        format!("{} {} {}", self.x, self.y, self.z)
    }
    /// Offset the position by an amount
    pub fn with_offset(&self, offset: MinecraftPosition) -> MinecraftPosition {
        // offsets do not affect facing direction.
        Self {
            x: self.x + offset.x,
            y: self.y + offset.y,
            z: self.z + offset.z,
            facing: self.facing,
        }
    }
}

// ==
// Minecraft Facing Direction
// ==

#[derive(Clone, Copy)]
/// The various directions that blocks can face.
pub enum MinecraftFacingDirection {
    North,
    East,
    South,
    West,
    Up,
    Down,
}

// TODO: impl rotate() to rotate the facing direction around an axis.

impl Display for MinecraftFacingDirection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MinecraftFacingDirection::North => write!(f, "north"),
            MinecraftFacingDirection::East => write!(f, "east"),
            MinecraftFacingDirection::South => write!(f, "south"),
            MinecraftFacingDirection::West => write!(f, "west"),
            MinecraftFacingDirection::Up => write!(f, "up"),
            MinecraftFacingDirection::Down => write!(f, "down"),
        }
    }
}
