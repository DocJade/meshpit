// See block_type for more detailed notes.
use std::borrow::Cow;

use mcdata_rs::Block;

use crate::minecraft::{
    computercraft::modded_data::get_modded_data, vanilla::data_globals::get_mc_data,
};

#[derive(Clone, Copy)]
pub struct MinecraftBlock {
    block: &'static Block,
}

impl MinecraftBlock {
    /// Get the name of this block as it would be used in commands. IE `minecraft:stone`
    pub fn get_full_name(&self) -> Cow<'static, str> {
        if !self.is_modded() {
            Cow::Borrowed(&self.block.name)
        } else {
            Cow::Owned(format!("computercraft:{}", self.block.name))
        }
    }
    /// Get the name of this block, not the display name.
    ///
    /// THIS CANNOT BE USED IN COMMANDS!
    pub fn get_name(&self) -> &String {
        &self.block.name
    }
    /// Get the display name of the block
    pub fn get_display_name(&self) -> &String {
        &self.block.display_name
    }
    /// Check if this is a modded block.
    fn is_modded(&self) -> bool {
        self.block.id & 1u32 << 31 != 0
    }
    /// Attempt to get an block from a block name.
    ///
    /// This does not work with modded block, such as computercraft floppies.
    /// //TODO: can this be fixed?
    pub fn from_string<T: AsRef<str> + std::hash::Hash + std::cmp::Eq + ?Sized>(
        name: &T,
    ) -> Option<Self>
    where
        std::string::String: std::borrow::Borrow<T>,
    {
        // this function has a lot of trait bounds to let us more easily pass in &str when making blocks.
        // this lets us do
        // Minecraftblock::from_string("gold_block").unwrap()
        // instead of
        // Minecraftblock::from_string(&"gold_block".into()).unwrap(),

        // first we try normal minecraft data, then we try modded data, since minecraft
        // data will be WAY more common.

        if let Some(block) = get_mc_data().blocks_by_name.get(name) {
            Some(Self { block })
        } else {
            // try getting the modded one, if its still not there, just return none.
            get_modded_data()
                .blocks_by_name
                .get(name)
                .map(|block| Self { block })
        }
    }
}
