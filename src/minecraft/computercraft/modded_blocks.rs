// see modded_Blocks for more info

use std::collections::HashMap;

use mcdata_rs::Block;
use once_cell::sync::Lazy;

pub(super) static MODDED_BLOCKS: Lazy<HashMap<String, Block>> = Lazy::new(|| {
    let mut m = HashMap::new();

    let mut ids: u32 = 1u32 << 31;

    // TODO: No idea how to do the floppy disk color variations, or turtle variations, will have to do that later.

    // TODO: I have no idea how to find the hardness values, actually, most of these values. But I can just make my best guess.

    // ===
    // Turtles
    // ===

    // computercraft:turtle_normal: Basic Turtle
    m.insert(
        "turtle_normal".to_string(),
        Block {
            id: ids,
            name: "turtle_normal".to_string(),
            display_name: "Turtle".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(), // this is prob irrelevant to us anyways.
            drops: vec![],                 // TODO:!!!! ITEM DROPS ON MODDED ITEMS!
            emit_light: 0,
            filter_light: 0,
            transparent: true, // i mean i guess?
            states: vec![],    // TODO: Do we need this?
            min_state_id: 0,   // these defaults to 0 in mcdata_rs
            max_state_id: 0,
            default_state: 0,
            state_id_map: None, // defaults to skip
        },
    );
    ids += 1;

    // computercraft:turtle_advanced: Advanced Turtle
    m.insert(
        "turtle_advanced".to_string(),
        Block {
            id: ids,
            name: "turtle_advanced".to_string(),
            display_name: "Advanced Turtle".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft: ?? : Mining Turtle
    // computercraft: ?? : Advanced Mining Turtle
    // etc

    // ===
    // Computers & Peripherals
    // ===

    // computercraft:computer_normal: Computer
    m.insert(
        "computer_normal".to_string(),
        Block {
            id: ids,
            name: "computer_normal".to_string(),
            display_name: "Computer".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:computer_advanced: Advanced Computer
    m.insert(
        "computer_advanced".to_string(),
        Block {
            id: ids,
            name: "computer_advanced".to_string(),
            display_name: "Advanced Computer".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft: ?? : Command Computer

    // pocket computers are not blocks.

    // computercraft:monitor_normal: Monitor
    m.insert(
        "monitor_normal".to_string(),
        Block {
            id: ids,
            name: "monitor_normal".to_string(),
            display_name: "Monitor".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:monitor_advanced: Advanced Monitor
    m.insert(
        "monitor_advanced".to_string(),
        Block {
            id: ids,
            name: "monitor_advanced".to_string(),
            display_name: "Advanced Monitor".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:printer: Printer
    m.insert(
        "printer".to_string(),
        Block {
            id: ids,
            name: "printer".to_string(),
            display_name: "Printer".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:disk_drive: Disk Drive
    m.insert(
        "disk_drive".to_string(),
        Block {
            id: ids,
            name: "disk_drive".to_string(),
            display_name: "Disk Drive".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:speaker: Speaker
    m.insert(
        "speaker".to_string(),
        Block {
            id: ids,
            name: "speaker".to_string(),
            display_name: "Speaker".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:wireless_modem_normal: Wireless Modem
    m.insert(
        "wireless_modem_normal".to_string(),
        Block {
            id: ids,
            name: "wireless_modem_normal".to_string(),
            display_name: "Wireless Modem".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(), // i mean, not really but kinda?
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:wireless_modem_advanced: Ender Modem
    m.insert(
        "wireless_modem_advanced".to_string(),
        Block {
            id: ids,
            name: "wireless_modem_advanced".to_string(),
            display_name: "Ender Modem".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:wired_modem: Wired Modem
    m.insert(
        "wired_modem".to_string(),
        Block {
            id: ids,
            name: "wired_modem".to_string(),
            display_name: "Wired Modem".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:wired_modem_full: Wired Modem
    // this is the full block variation
    m.insert(
        "wired_modem_full".to_string(),
        Block {
            id: ids,
            name: "wired_modem_full".to_string(),
            display_name: "Wired Modem".to_string(), // has the same display name though.
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:redstone_relay: Redstone Relay
    m.insert(
        "redstone_relay".to_string(),
        Block {
            id: ids,
            name: "redstone_relay".to_string(),
            display_name: "Redstone Relay".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    ids += 1;

    // computercraft:cable: Networking Cable
    m.insert(
        "cable".to_string(),
        Block {
            id: ids,
            name: "cable".to_string(),
            display_name: "Networking Cable".to_string(),
            stack_size: 64,
            variations: None,
            hardness: None,
            resistance: 0.0,
            diggable: true,
            bounding_box: "block".to_string(),
            material: None,
            harvest_tools: HashMap::new(),
            drops: vec![],
            emit_light: 0,
            filter_light: 0,
            transparent: true,
            states: vec![],
            min_state_id: 0,
            max_state_id: 0,
            default_state: 0,
            state_id_map: None,
        },
    );
    // ids += 1;

    // skipping all items
    m
});

// ===
// Tests
// ===

#[cfg(test)]
use crate::minecraft::vanilla::data_globals::get_mc_data;

#[test]
/// Make sure that all of the Block ID's, Block names, and display names are unique.
///
/// Make sure that these Blocks do not collide with the normal Minecraft Blocks.
///
/// Make sure that all the Blocks' keys are the same as their names.
fn check_modded_blocks() {
    let mut modded_values: Vec<Block> = MODDED_BLOCKS.clone().into_values().collect();
    // yeah idk what this is either
    let mut vanilla_values: Vec<Block> = <std::collections::HashMap<
        std::string::String,
        mcdata_rs::Block,
    > as Clone>::clone(&get_mc_data().blocks_by_name)
    .into_values()
    .collect();

    // Sort the vec by id
    modded_values.sort_unstable_by_key(|block| block.id);
    vanilla_values.sort_unstable_by_key(|block| block.id);

    // check for duplicate Block id's per vec
    let mut modded_dedup = modded_values.clone();
    modded_dedup.dedup_by(|a, b| a.id == b.id);
    assert_eq!(modded_dedup.len(), modded_values.len());

    let mut vanilla_dedup = vanilla_values.clone();
    vanilla_dedup.dedup_by(|a, b| a.id == b.id);
    assert_eq!(vanilla_dedup.len(), vanilla_values.len());

    // check if any Block id is in both vecs
    // this is easily done by just combining the vecs and sorting again.
    let mut combined: Vec<Block> = Vec::with_capacity(vanilla_dedup.len() + modded_dedup.len());
    combined.extend(vanilla_dedup);
    combined.extend(modded_dedup);
    // this should already be in order anyways, if all goes well.
    combined.sort_unstable_by_key(|block| block.id);
    let combine_length = combined.len();
    combined.dedup_by(|a, b| a.id == b.id);
    assert_eq!(combined.len(), combine_length);

    // Check for duplicate Block names
    combined.dedup_by(|a, b| a.name == b.name);
    assert_eq!(combined.len(), combine_length);

    // We dont check for duplicate display names, since that is a normal thing to have.

    // check that the keys match the modded Block names.
    let modded_values_two = &MODDED_BLOCKS;
    for (key, value) in modded_values_two.iter() {
        assert_eq!(key, &value.name)
    }
}
