// Generic inventories.

use std::collections::HashMap;

use serde::Deserialize;

use crate::minecraft::vanilla::item_type::MinecraftItem;

// TODO: if we implement the methods as a trait, then it would be easier to add new things.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct GenericInventory {
    /// The size of the inventory, IE how many slots it has.
    pub size: u16,
    /// The individual slots in the inventory of this turtle.
    pub slots: Vec<Option<GenericInventorySlot>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
pub struct GenericInventorySlot {
    // What item is in this slot.
    pub item: MinecraftItem,
    /// How many of that item are in the slot.
    pub count: u8,
}
