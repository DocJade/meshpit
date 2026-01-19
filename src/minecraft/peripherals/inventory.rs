// Generic inventories.

use std::collections::HashMap;

use crate::minecraft::vanilla::item_type::MinecraftItem;

// TODO: if we implement the methods as a trait, then it would be easier to add new things.
pub struct GenericInventory {
    /// The size of the inventory, IE how many slots it has.
    size: u16,
    /// The individual slots in the inventory of this turtle.
    slots: HashMap<u16, GenericInventorySlot>,
}

pub struct GenericInventorySlot {
    // What item is in this slot.
    item: Option<MinecraftItem>,
    /// How many of that item are in the slot.
    count: Option<u8>,
}
