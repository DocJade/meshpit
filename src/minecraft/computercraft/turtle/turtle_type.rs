// The turtle!

use crate::minecraft::{
    peripherals::inventory::GenericInventory,
    types::{MinecraftFacingDirection, MinecraftPosition},
};

pub struct Turtle {
    /// The ID of this Turtle.
    id: u16,
    /// The current position of the Turtle.
    ///
    /// TODO: we dont want to make this an option, but if we dont know the position of a turtle, we need to signal that somehow.
    position: MinecraftPosition,
    /// What direction the Turtle is facing.
    facing: MinecraftFacingDirection,
    /// How much fuel the Turtle currently has.
    fuel_level: u16,
    /// The inventory of the Turtle
    inventory: GenericInventory,
}
