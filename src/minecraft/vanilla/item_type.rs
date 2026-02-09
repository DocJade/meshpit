// The basic Minecraft item type.
// This is our base type for every kind of item in Minecraft, this can also be cast to MinecraftBlock (TODO: if i ever do that or need it)

use mcdata_rs::Item;
use std::borrow::Cow;

use crate::minecraft::{
    computercraft::modded_data::get_modded_data, vanilla::data_globals::get_mc_data,
};

#[derive(Debug, Clone, Copy)]
pub struct MinecraftItem {
    // The inner mcdata item type. We make this wrapper MinecraftItem type so we
    // can implement new methods on it.
    // This is zero cost bc rust i think lol - Doc
    //
    // Also, since the item data it references is static, we can make this static as well.
    /// The inner item type
    item: &'static Item,
}

// Implementation of equality
impl PartialEq for MinecraftItem {
    fn eq(&self, _other: &Self) -> bool {
        todo!("Item equality checks.")
    }
}

// On our implementations, we avoid using owned strings, since we don't want to constantly be cloning.
// Apparently even if you don't update the string, cloning a String type is always a deep clone, which
// is slow.

impl MinecraftItem {
    /// Get the name of this item as it would be used in commands. IE `minecraft:stone`
    pub fn get_full_name(&self) -> Cow<'static, str> {
        // why a Cow<>?
        // We can skip the allocation for a new string from &self here, which saves... probably
        // such an insignificant amount of time that it hardly matters, but why not? :D
        // This may be an issue for multithreading later though, !remindme 10,000 years
        if !self.is_modded() {
            // Minecraft will automatically add `minecraft:` to the name if you do not specify,
            // so we dont need to do anything here.
            Cow::Borrowed(&self.item.name)
        } else {
            // we assume the only mod is computercraft for obvious reasons.
            Cow::Owned(format!("computercraft:{}", self.item.name))
        }
    }
    /// Get the name of this item, not the display name.
    ///
    /// THIS CANNOT BE USED IN COMMANDS!
    pub fn get_name(&self) -> &String {
        &self.item.name
    }
    /// Get the display name of the item
    pub fn get_display_name(&self) -> &String {
        &self.item.display_name
    }
    /// Check if this is a modded item.
    fn is_modded(&self) -> bool {
        // check the modded bit
        self.item.id & 1u32 << 31 != 0
    }
    /// Attempt to get an item from a item name.
    ///
    /// This does not work with modded items, such as computercraft floppies.
    /// //TODO: can this be fixed?
    pub fn from_string<T: AsRef<str> + std::hash::Hash + std::cmp::Eq + ?Sized>(
        name: &T,
    ) -> Option<Self>
    where
        std::string::String: std::borrow::Borrow<T>,
    {
        // this function has a lot of trait bounds to let us more easily pass in &str when making items.
        // this lets us do
        // MinecraftItem::from_string("gold_block").unwrap()
        // instead of
        // MinecraftItem::from_string(&"gold_block".into()).unwrap(),

        // first we try normal minecraft data, then we try modded data, since minecraft
        // data will be WAY more common.

        if let Some(item) = get_mc_data().items_by_name.get(name) {
            Some(Self { item })
        } else {
            // try getting the modded one, if its still not there, just return none.
            get_modded_data()
                .items_by_name
                .get(name)
                .map(|item| Self { item })
        }
    }
}

// ======
// Deserialization
// ======

impl<'de> serde::de::Deserialize<'de> for MinecraftItem {
    fn deserialize<D>(_deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        todo!("Implement minecraft item deserializer.")
    }
}
