// See block_type for more detailed notes.
use std::borrow::Cow;

use log::info;
use mcdata_rs::{Block, BlockStateDefinition};
use serde::de::Error;
use serde::{Deserialize, de::IgnoredAny}; // Import the trait!

use crate::minecraft::types::CoordinatePosition;
use crate::minecraft::{
    computercraft::modded_data::get_modded_data, vanilla::data_globals::get_mc_data,
};

#[derive(Clone, Debug)]
pub struct MinecraftBlock {
    /// The inner block.
    block: Block,
}

/// Trait that both block types implement due to holding the underlying block type.
pub trait HasMinecraftBlock {
    /// Get the name of this block, not the display name.
    ///
    /// THIS CANNOT BE USED IN COMMANDS!
    fn get_name(&self) -> &String;

    /// Get the display name of the block
    fn get_display_name(&self) -> &String;

    /// Check if this is a modded block.
    fn is_modded(&self) -> bool;

    /// Get the name of this block as it would be used in commands. IE `minecraft:stone`
    fn get_full_name(&self) -> Cow<'_, String>;
}

/// A block that actually has a position. The two layers of abstraction are fine
/// since they're removed at compile time (?)
#[derive(Clone, Debug, Deserialize)]
#[serde(try_from = "LuaBlock")]
pub struct PositionedMinecraftBlock {
    /// The inner block.
    block: MinecraftBlock,
    /// The position that this block is at.
    position: CoordinatePosition,
}

impl HasMinecraftBlock for PositionedMinecraftBlock {
    fn get_name(&self) -> &String {
        self.block.get_name()
    }

    fn get_display_name(&self) -> &String {
        self.block.get_display_name()
    }

    fn is_modded(&self) -> bool {
        self.block.is_modded()
    }

    fn get_full_name(&self) -> Cow<'_, String> {
        self.block.get_full_name()
    }
}

impl MinecraftBlock {
    /// Attempt to get an block from a block name.
    ///
    /// This does not work with modded block, such as computercraft floppies.
    /// //TODO: can this be fixed?
    pub fn from_string<T: AsRef<str> + ?Sized>(name: &T) -> Option<Self> {
        // this function has a lot of trait bounds to let us more easily pass in &str when making blocks.
        // this lets us do
        // Minecraftblock::from_string("gold_block").unwrap()
        // instead of
        // Minecraftblock::from_string(&"gold_block".into()).unwrap(),

        // first we try normal minecraft data, then we try modded data, since minecraft
        // data will be WAY more common.

        // If the string is pre-pended with `minecraft` or `computercraft` we ignore it
        let name_only = name.as_ref().split(":").last().unwrap_or(name.as_ref());

        if let Some(block) = get_mc_data().blocks_by_name.get(name_only).cloned() {
            Some(Self { block })
        } else {
            // try getting the modded one, if its still not there, just return none.
            get_modded_data()
                .blocks_by_name
                .get(name_only)
                .cloned()
                .map(|block| Self { block })
        }
    }
}

impl HasMinecraftBlock for MinecraftBlock {
    fn get_name(&self) -> &String {
        &self.block.name
    }

    fn get_display_name(&self) -> &String {
        &self.block.display_name
    }

    fn is_modded(&self) -> bool {
        self.block.id & 1u32 << 31 != 0
    }

    fn get_full_name(&self) -> Cow<'_, String> {
        if !self.is_modded() {
            Cow::Owned(format!("minecraft:{}", self.block.name))
        } else {
            Cow::Owned(format!("computercraft:{}", self.block.name))
        }
    }
}

// ======
// Lua side types
// ======

// {"state":null,"tag":null,"name":"minecraft:dirt","pos":{"y":2,"x":1,"z":1}}

/// The lua side uses a different block format
///
/// ---@class Block
/// ---@field pos CoordPosition
/// ---@field state MinecraftBlockState[]
/// ---@field tag MinecraftBlockTag[]
/// ---@field name string
#[derive(Debug, Deserialize)]
pub struct LuaBlock {
    name: String,
    pos: CoordinatePosition,
    state: Option<Vec<LuaMinecraftBlockState>>,
    // We can completely ignore tags, as they are static and aren't dynamically
    // added to blocks
    #[serde(skip)]
    #[serde(rename = "tag")]
    _tags: IgnoredAny,
}

/// We need to be able to convert back and forth between the basic lua block
/// states that we store on the lua side, and the cool rust one.
#[derive(Debug, Deserialize)]
enum LuaMinecraftBlockState {
    #[serde(rename = "age")]
    Age(u32),
    #[serde(rename = "eye")]
    Eye(bool),
    #[serde(rename = "honey_level")]
    HoneyLevel(u32),
    #[serde(rename = "level")]
    Level(u32),
    #[serde(rename = "lit")]
    Lit(bool),
    #[serde(rename = "stage")]
    Stage(u32),
}

/// Convert the block states
impl From<LuaMinecraftBlockState> for BlockStateDefinition {
    fn from(value: LuaMinecraftBlockState) -> BlockStateDefinition {
        // No idea what it wants here, really just completely guessing how
        // all of this is used. TODO: how can we test this
        let name: String;
        let state_type: String;
        let num_values: Option<u32>;
        let values: Vec<String>;
        match value {
            LuaMinecraftBlockState::Age(number) => {
                name = "age".into();
                state_type = "int".into();
                num_values = Some(number);
                values = Vec::new();
            }
            LuaMinecraftBlockState::Eye(boolean) => {
                let num = if boolean { 1 } else { 0 };
                name = "eye".into();
                state_type = "bool".into();
                num_values = Some(num);
                values = Vec::new();
            }
            LuaMinecraftBlockState::HoneyLevel(number) => {
                name = "honey_level".into();
                state_type = "int".into();
                num_values = Some(number);
                values = Vec::new();
            }
            LuaMinecraftBlockState::Level(number) => {
                name = "level".into();
                state_type = "int".into();
                num_values = Some(number);
                values = Vec::new();
            }
            LuaMinecraftBlockState::Lit(boolean) => {
                let num = if boolean { 1 } else { 0 };
                name = "lit".into();
                state_type = "bool".into();
                num_values = Some(num);
                values = Vec::new();
            }
            LuaMinecraftBlockState::Stage(number) => {
                name = "stage".into();
                state_type = "int".into();
                num_values = Some(number);
                values = Vec::new();
            }
        };
        BlockStateDefinition {
            name,
            state_type,
            num_values,
            values,
        }
    }
}

/// Attempt to convert a lua block into a PositionedMinecraftBlock
impl TryFrom<LuaBlock> for PositionedMinecraftBlock {
    type Error = String;

    fn try_from(value: LuaBlock) -> Result<Self, Self::Error> {
        let mut unconfigured = MinecraftBlock::from_string(&value.name).ok_or("Unknown block")?;
        // TODO: I have no idea if this is gonna work lmao.
        let new_states: Vec<BlockStateDefinition> = if let Some(lua_states) = value.state {
            lua_states.into_iter().map(|i| i.into()).collect()
        } else {
            Vec::new()
        };

        unconfigured.block.states = new_states;
        let done = PositionedMinecraftBlock {
            block: unconfigured,
            position: value.pos,
        };

        Ok(done)
    }
}

// ======
// Deserialization
// ======

// impl<'de> serde::de::Deserialize<'de> for PositionedMinecraftBlock {
//     fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
//     where
//         D: serde::Deserializer<'de> {
//         // First convert into the lua type
//         info!("Attempting to cast to lua block...");
//         let lua_block = LuaBlock::deserialize(deserializer).unwrap();
//         info!("Casted.");

//         // Then convert to the actual block type, or fail if that does not work.
//         PositionedMinecraftBlock::try_from(lua_block).map_err(|_| D::Error::custom("unknown block"))
//     }
// }
