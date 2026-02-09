// Minecraft related types

// ==
// Minecraft Position
// ==

use std::{fmt::Display, str::FromStr};

use regex::Regex;
use serde::Deserialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
/// The world position of something in Minecraft.
///
/// This may contain a facing direction, but is not mandatory.
pub struct MinecraftPosition {
    pub position: CoordinatePosition,
    pub facing: Option<MinecraftCardinalDirection>,
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
    pub const fn move_direction(&mut self, direction: MinecraftCardinalDirection) {
        self.position = self.position.with_offset(direction.move_towards());
    }
}

// ==
// Minecraft Facing Direction
// ==

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
/// The various directions that blocks can face.
pub enum MinecraftCardinalDirection {
    #[serde(rename = "n")]
    North, // -Z
    #[serde(rename = "e")]
    East, // +X
    #[serde(rename = "s")]
    South, // +Z
    #[serde(rename = "w")]
    West, // -X
    #[serde(rename = "u")]
    Up, // +Y
    #[serde(rename = "d")]
    Down, // -Y
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum TurnDirection {
    Left,
    Right,
}

impl MinecraftCardinalDirection {
    /// Rotate the facing direction of this position.
    ///
    /// Does nothing on up or down facing.
    pub const fn rotate(&mut self, direction: TurnDirection) {
        // yes this is lazy
        *self = match direction {
            TurnDirection::Right => match self {
                MinecraftCardinalDirection::North => MinecraftCardinalDirection::East,
                MinecraftCardinalDirection::East => MinecraftCardinalDirection::South,
                MinecraftCardinalDirection::South => MinecraftCardinalDirection::West,
                MinecraftCardinalDirection::West => MinecraftCardinalDirection::North,
                _ => *self,
            },
            TurnDirection::Left => match self {
                MinecraftCardinalDirection::North => MinecraftCardinalDirection::West,
                MinecraftCardinalDirection::West => MinecraftCardinalDirection::South,
                MinecraftCardinalDirection::South => MinecraftCardinalDirection::East,
                MinecraftCardinalDirection::East => MinecraftCardinalDirection::North,
                _ => *self,
            },
        };
    }
    /// Get a positional offset that moves 1 unit along the provided direction.
    ///
    /// This returns an offset, not a new position.
    pub const fn move_towards(&self) -> CoordinatePosition {
        match self {
            MinecraftCardinalDirection::North => CoordinatePosition { x: 0, y: 0, z: -1 },
            MinecraftCardinalDirection::East => CoordinatePosition { x: 1, y: 0, z: 0 },
            MinecraftCardinalDirection::South => CoordinatePosition { x: 0, y: 0, z: 1 },
            MinecraftCardinalDirection::West => CoordinatePosition { x: -1, y: 0, z: 0 },
            MinecraftCardinalDirection::Up => CoordinatePosition { x: 0, y: 1, z: 0 },
            MinecraftCardinalDirection::Down => CoordinatePosition { x: 0, y: -1, z: 0 },
        }
    }
}

impl Display for MinecraftCardinalDirection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MinecraftCardinalDirection::North => write!(f, "north"),
            MinecraftCardinalDirection::East => write!(f, "east"),
            MinecraftCardinalDirection::South => write!(f, "south"),
            MinecraftCardinalDirection::West => write!(f, "west"),
            MinecraftCardinalDirection::Up => write!(f, "up"),
            MinecraftCardinalDirection::Down => write!(f, "down"),
        }
    }
}

// ==
// Coordinates
// ==

// Need to be able to derive these from either a string or from a matching struct,
// so this takes some special work.

#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize, Hash)]
#[serde(try_from = "CoordinatePositionVariant")]
/// A position in XYZ space with no facing component.
pub struct CoordinatePosition {
    /// East, West
    pub x: i64,
    /// Up, Down
    pub y: i64,
    /// North, South
    pub z: i64,
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
// Casting nonsense
// ==

#[derive(Deserialize)]
#[serde(untagged)]
enum CoordinatePositionVariant {
    Map { x: i64, y: i64, z: i64 },
    String(String),
}

impl TryFrom<CoordinatePositionVariant> for CoordinatePosition {
    type Error = String;

    fn try_from(value: CoordinatePositionVariant) -> Result<Self, Self::Error> {
        match value {
            CoordinatePositionVariant::Map { x, y, z } => Ok(Self { x, y, z }),
            CoordinatePositionVariant::String(das_string) => {
                Ok(CoordinatePosition::from_str(&das_string)?)
            }
        }
    }
}

/// Attempt to pull a coordinate position from a string. Errors with unit type if
/// this is not a coordinate.
impl std::str::FromStr for CoordinatePosition {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        // Capture groups for xyz, anchored on start and end so must match all 3
        let regex = Regex::new(r"^x:(-?\d+)\|y:(-?\d+)\|z:(-?\d+)$").expect("This is valid regex.");

        // Captured?
        // If not, return early
        let captures = regex.captures(s).ok_or("no capture")?;

        // Got it, captures
        Ok(Self {
            x: captures[1].parse().map_err(|_| "invalid x integer")?,
            y: captures[2].parse().map_err(|_| "invalid y integer")?,
            z: captures[3].parse().map_err(|_| "invalid z integer")?,
        })
    }
}

// #[serde(try_from = "String")]
impl TryFrom<String> for CoordinatePosition {
    type Error = String;
    fn try_from(s: String) -> Result<Self, Self::Error> {
        s.parse()
    }
}
