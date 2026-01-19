use std::{collections::HashMap, sync::Arc};

use mcdata_rs::*;
use once_cell::sync::Lazy;
// use serde_json::Value;

use crate::minecraft::computercraft::{modded_blocks::MODDED_BLOCKS, modded_items::MODDED_ITEMS};

//TODO: id fields for easier/faster casting
static MODDED_DATA: Lazy<Arc<ModdedIndexedData>> = Lazy::new(|| {
    ModdedIndexedData {
        // this clone only happens once at startup, shouldn't be a huge deal.
        items_by_name: Arc::new((*MODDED_ITEMS).clone()),
        blocks_by_name: Arc::new((*MODDED_BLOCKS).clone()),
    }
    .into()
});

pub fn get_modded_data() -> &'static ModdedIndexedData {
    #[allow(clippy::explicit_auto_deref)] // want to show the deref happening
    &**MODDED_DATA
}

/// copy of the minecraft indexed data struct, so code is cleaner. yes this is goofy af.
///
/// We dont keep any of the fields that we do not use.
#[derive(Debug, Clone)]
pub struct ModdedIndexedData {
    /// The canonical `Version` struct this data corresponds to.
    // pub version: Version,

    // Indexed data structures for quick lookups.

    // Blocks
    // pub blocks_array: Arc<Vec<Block>>,
    // pub blocks_by_id: Arc<HashMap<u32, Block>>,
    pub blocks_by_name: Arc<HashMap<String, Block>>,
    // pub blocks_by_state_id: Arc<HashMap<u32, Block>>,

    // Items
    // pub items_array: Arc<Vec<Item>>,
    // pub items_by_id: Arc<HashMap<u32, Item>>,
    pub items_by_name: Arc<HashMap<String, Item>>,
    // Biomes
    // pub biomes_array: Arc<Vec<Biome>>,
    // pub biomes_by_id: Arc<HashMap<u32, Biome>>,
    // pub biomes_by_name: Arc<HashMap<String, Biome>>,

    // Effects (Status Effects)
    // pub effects_array: Arc<Vec<Effect>>,
    // pub effects_by_id: Arc<HashMap<u32, Effect>>,
    // pub effects_by_name: Arc<HashMap<String, Effect>>,

    // Entities
    // pub entities_array: Arc<Vec<Entity>>,
    // pub entities_by_id: Arc<HashMap<u32, Entity>>,
    // pub entities_by_name: Arc<HashMap<String, Entity>>,
    // pub mobs_by_id: Arc<HashMap<u32, Entity>>, // Filtered index for entities of type "mob"
    // pub objects_by_id: Arc<HashMap<u32, Entity>>, // Filtered index for entities of type "object"

    // Sounds
    // pub sounds_array: Arc<Vec<Sound>>,
    // pub sounds_by_id: Arc<HashMap<u32, Sound>>,
    // pub sounds_by_name: Arc<HashMap<String, Sound>>,

    // Particles
    // pub particles_array: Arc<Vec<Particle>>,
    // pub particles_by_id: Arc<HashMap<u32, Particle>>,
    // pub particles_by_name: Arc<HashMap<String, Particle>>,

    // Attributes
    // pub attributes_array: Arc<Vec<Attribute>>,
    // pub attributes_by_name: Arc<HashMap<String, Attribute>>,
    // pub attributes_by_resource: Arc<HashMap<String, Attribute>>, // Index by namespaced key

    // Instruments (Note Block sounds)
    // pub instruments_array: Arc<Vec<Instrument>>,
    // pub instruments_by_id: Arc<HashMap<u32, Instrument>>,
    // pub instruments_by_name: Arc<HashMap<String, Instrument>>,

    // Foods
    // pub foods_array: Arc<Vec<Food>>,
    // pub foods_by_id: Arc<HashMap<u32, Food>>,
    // pub foods_by_name: Arc<HashMap<String, Food>>,

    // Enchantments
    // pub enchantments_array: Arc<Vec<Enchantment>>,
    // pub enchantments_by_id: Arc<HashMap<u32, Enchantment>>,
    // pub enchantments_by_name: Arc<HashMap<String, Enchantment>>,

    // Map Icons
    // pub map_icons_array: Arc<Vec<MapIcon>>,
    // pub map_icons_by_id: Arc<HashMap<u32, MapIcon>>,
    // pub map_icons_by_name: Arc<HashMap<String, MapIcon>>,

    // Windows (Containers/GUIs)
    // pub windows_array: Arc<Vec<Window>>,
    // pub windows_by_id: Arc<HashMap<String, Window>>, // Index by ID (string, potentially namespaced)
    // pub windows_by_name: Arc<HashMap<String, Window>>,

    // Block Loot Tables
    // pub block_loot_array: Arc<Vec<BlockLoot>>,
    // pub block_loot_by_name: Arc<HashMap<String, BlockLoot>>, // Index by block name

    // Entity Loot Tables
    // pub entity_loot_array: Arc<Vec<EntityLoot>>,
    // pub entity_loot_by_name: Arc<HashMap<String, EntityLoot>>, // Index by entity name

    // Indexed Block Collision Shapes
    // pub block_shapes_by_state_id: Arc<HashMap<u32, Vec<[f64; 6]>>>, // Map stateId -> BoundingBoxes
    // pub block_shapes_by_name: Arc<HashMap<String, Vec<[f64; 6]>>>, // Map blockName -> Default State BoundingBoxes

    // Less structured or version-dependent data.
    // /// Raw data from blockCollisionShapes.json, if available for the version.
    // pub block_collision_shapes_raw: Arc<Option<BlockCollisionShapes>>,
    // /// Data from tints.json, if available.
    // pub tints: Arc<Option<Tints>>,
    // /// Data from language.json (typically en_us), if available.
    // pub language: Arc<HashMap<String, String>>,
    // /// Data from legacy.json (mapping old IDs to new), if available.
    // pub legacy: Arc<Option<Legacy>>,

    // Raw JSON values for data types that vary significantly across versions
    // or are too complex to represent with stable structs easily.
    // pub recipes: Arc<Option<Value>>,
    // pub materials: Arc<Option<Value>>,
    // pub commands: Arc<Option<Value>>,
    // pub protocol: Arc<Option<Value>>, // Raw protocol.json content
    // pub protocol_comments: Arc<Option<Value>>, // Raw protocolComments.json content
    // pub login_packet: Arc<Option<Value>>, // Raw loginPacket.json content
}
