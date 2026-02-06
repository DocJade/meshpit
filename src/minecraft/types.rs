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
    pub position: CoordinatePosition,
    pub facing: Option<MinecraftFacingDirection>,
}

#[derive(Clone, Copy)]
/// A position in XYZ space with no facing component.
pub struct CoordinatePosition {
    /// East, West
    pub x: i64,
    /// Up, Down
    pub y: i64,
    /// North, South
    pub z: i64,
}

impl MinecraftPosition {
    /// Get the position as a string, used in commands (no commas). Does not
    /// contain any facing information.
    pub fn as_command_string(&self) -> String {
        self.position.as_command_string()
    }
    /// Offset the position with an incoming coordinate position.
    pub const fn with_offset(&self, offset: CoordinatePosition) -> Self {
        // offsets do not affect facing direction.
        Self {
            position: CoordinatePosition {
                x: self.position.x + offset.x,
                y: self.position.y + offset.y,
                z: self.position.z + offset.z,
            },
            facing: self.facing,
        }
    }
    /// Move in a specified cardinal direction.
    pub const fn move_direction(&mut self, direction: MinecraftFacingDirection) {
        self.position.with_offset(direction.move_towards());
    }
}

impl CoordinatePosition {
    /// Offset the position with an incoming coordinate position.
    pub const fn with_offset(&self, offset: CoordinatePosition) -> Self {
        // offsets do not affect facing direction.
        Self {
            x: self.x + offset.x,
            y: self.y + offset.y,
            z: self.z + offset.z,
        }
    }
    /// Get the position as a string, used in commands (no commas).
    pub fn as_command_string(&self) -> String {
        format!("{} {} {}", self.x, self.y, self.z)
    }
}

// ==
// Minecraft Facing Direction
// ==

#[derive(Clone, Copy)]
/// The various directions that blocks can face.
pub enum MinecraftFacingDirection {
    North,  // -Z
    East,   // +X
    South,  // +Z
    West,   // -X
    Up,     // +Y
    Down,   // -Y
}

#[derive(PartialEq, Eq)]
pub enum TurnDirection {
    Left,
    Right
}

impl MinecraftFacingDirection {
    /// Rotate the facing direction of this position.
    /// 
    /// Does nothing on up or down facing.
    pub const fn rotate(&mut self, direction: TurnDirection) {
        // yes this is lazy
        *self = match direction {
            TurnDirection::Right => match self {
                MinecraftFacingDirection::North => MinecraftFacingDirection::East,
                MinecraftFacingDirection::East => MinecraftFacingDirection::South,
                MinecraftFacingDirection::South => MinecraftFacingDirection::West,
                MinecraftFacingDirection::West => MinecraftFacingDirection::North,
                _ => *self,
            },
            TurnDirection::Left => match self {
                MinecraftFacingDirection::North => MinecraftFacingDirection::West,
                MinecraftFacingDirection::West => MinecraftFacingDirection::South,
                MinecraftFacingDirection::South => MinecraftFacingDirection::East,
                MinecraftFacingDirection::East => MinecraftFacingDirection::North,
                _ => *self,
            },
        };
    }
    /// Get a positional offset that moves 1 unit along the provided direction.
    /// 
    /// This returns an offset, not a new position.
    pub const fn move_towards(&self) -> CoordinatePosition {
        match self {
            MinecraftFacingDirection::North => CoordinatePosition { x: 0, y: 0, z: -1 },
            MinecraftFacingDirection::East => CoordinatePosition { x: 1, y: 0, z: 0 },
            MinecraftFacingDirection::South => CoordinatePosition { x: 0, y: 0, z: 1 },
            MinecraftFacingDirection::West => CoordinatePosition { x: -1, y: 0, z: 0 },
            MinecraftFacingDirection::Up => CoordinatePosition { x: 0, y: 1, z: 0 },
            MinecraftFacingDirection::Down => CoordinatePosition { x: 0, y: -1, z: 0 },
        }
    }
}

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
