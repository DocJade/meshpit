// since we want to use the singular block modeling struct, we need to be able to use
// modded computercraft items as well in that struct, which means we need to spoof them ourselves.
// hence why we do that manually here. Otherwise it would be a mess with multiple types.

use std::collections::HashMap;

use mcdata_rs::Item;
use once_cell::sync::Lazy;

pub(super) static MODDED_ITEMS: Lazy<HashMap<String, Item>> = Lazy::new(|| {
    let mut m = HashMap::new();

    // Since we want our item ID's to be WAY out of range, we use a large number here to make sure
    // that they do not collide with the other normal items.
    // And since we're clever, we'll pick a nice number to start at so the compiler knows it only
    // has to check one bit.
    //
    // The highest number I see in the json file is ~1300, so we have plenty of room in the u32,
    // thus we'll just flip the most significant bit.
    //
    // WARNING: If you change this offset number, any database with these ID's will just break, since the
    // unique ids are no-longer correlated.

    // 0b1000_0000_0000_0000
    let mut ids: u32 = 1u32 << 31;

    // Annoyingly, this process is manual.

    // TODO: No idea how to do the floppy disk color variations, or turtle variations, will have to do that later.

    // ===
    // Turtles
    // ===

    // computercraft:turtle_normal: Basic Turtle
    m.insert(
        "turtle_normal".to_string(),
        Item {
            id: ids,
            name: "turtle_normal".to_string(),
            display_name: "Turtle".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:turtle_advanced: Advanced Turtle
    m.insert(
        "turtle_advanced".to_string(),
        Item {
            id: ids,
            name: "turtle_advanced".to_string(),
            display_name: "Advanced Turtle".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
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
        Item {
            id: ids,
            name: "computer_normal".to_string(),
            display_name: "Computer".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:computer_advanced: Advanced Computer
    m.insert(
        "computer_advanced".to_string(),
        Item {
            id: ids,
            name: "computer_advanced".to_string(),
            display_name: "Advanced Computer".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft: ?? : Command Computer

    // computercraft:pocket_computer_normal: Pocket Computer
    m.insert(
        "pocket_computer_normal".to_string(),
        Item {
            id: ids,
            name: "pocket_computer_normal".to_string(),
            display_name: "Pocket Computer".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:pocket_computer_advanced: Advanced Pocket Computer
    m.insert(
        "pocket_computer_advanced".to_string(),
        Item {
            id: ids,
            name: "pocket_computer_advanced".to_string(),
            display_name: "Advanced Pocket Computer".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // etc pocket computer variations

    // computercraft:monitor_normal: Monitor
    m.insert(
        "monitor_normal".to_string(),
        Item {
            id: ids,
            name: "monitor_normal".to_string(),
            display_name: "Monitor".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:monitor_advanced: Advanced Monitor
    m.insert(
        "monitor_advanced".to_string(),
        Item {
            id: ids,
            name: "monitor_advanced".to_string(),
            display_name: "Advanced Monitor".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:printer: Printer
    m.insert(
        "printer".to_string(),
        Item {
            id: ids,
            name: "printer".to_string(),
            display_name: "Printer".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:disk_drive: Disk Drive
    m.insert(
        "disk_drive".to_string(),
        Item {
            id: ids,
            name: "disk_drive".to_string(),
            display_name: "Disk Drive".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:speaker: Speaker
    m.insert(
        "speaker".to_string(),
        Item {
            id: ids,
            name: "speaker".to_string(),
            display_name: "Speaker".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:wireless_modem_normal: Wireless Modem
    m.insert(
        "wireless_modem_normal".to_string(),
        Item {
            id: ids,
            name: "wireless_modem_normal".to_string(),
            display_name: "Wireless Modem".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:wireless_modem_advanced: Ender Modem
    m.insert(
        "wireless_modem_advanced".to_string(),
        Item {
            id: ids,
            name: "wireless_modem_advanced".to_string(),
            display_name: "Ender Modem".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:wired_modem: Wired Modem
    m.insert(
        "wired_modem".to_string(),
        Item {
            id: ids,
            name: "wired_modem".to_string(),
            display_name: "Wired Modem".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:wired_modem_full: Wired Modem
    // this is the full block variation
    m.insert(
        "wired_modem_full".to_string(),
        Item {
            id: ids,
            name: "wired_modem_full".to_string(),
            display_name: "Wired Modem".to_string(), // has the same display name though.
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:redstone_relay: Redstone Relay
    m.insert(
        "redstone_relay".to_string(),
        Item {
            id: ids,
            name: "redstone_relay".to_string(),
            display_name: "Redstone Relay".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:cable: Networking Cable
    m.insert(
        "cable".to_string(),
        Item {
            id: ids,
            name: "cable".to_string(),
            display_name: "Networking Cable".to_string(),
            stack_size: 64,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // ===
    // Items
    // ===

    // computercraft:disk: Floppy Disk
    m.insert(
        "disk".to_string(),
        Item {
            id: ids,
            name: "disk".to_string(),
            display_name: "Floppy Disk".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // floppy disk color variations

    // computercraft:printed_page: Printed Page
    m.insert(
        "printed_page".to_string(),
        Item {
            id: ids,
            name: "printed_page".to_string(),
            display_name: "Printed Page".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:printed_pages: Printed Pages
    m.insert(
        "printed_pages".to_string(),
        Item {
            id: ids,
            name: "printed_pages".to_string(),
            display_name: "Printed Pages".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    ids += 1;

    // computercraft:printed_book: Printed Book
    m.insert(
        "printed_book".to_string(),
        Item {
            id: ids,
            name: "printed_book".to_string(),
            display_name: "Printed Book".to_string(),
            stack_size: 1,
            enchant_categories: None,
            repair_with: None,
            max_durability: None,
            variations: None,
        },
    );
    // ids += 1;

    m
});

// ===
// Tests
// ===

#[cfg(test)]
use crate::minecraft::computercraft::modded_data::get_modded_data;
#[cfg(test)]
use crate::minecraft::vanilla::data_globals::get_mc_data;

#[test]
/// Make sure that all of the Item ID's, item names, and display names are unique.
///
/// Make sure that these items do not collide with the normal Minecraft items.
///
/// Make sure that all the items' keys are the same as their names.
fn check_modded_items() {
    let modded_values: &mut Vec<&Item> = &mut get_modded_data().items_by_name.values().collect();
    let vanilla_values: &mut Vec<&Item> = &mut get_mc_data().items_by_name.values().collect();

    // Sort the vec by id
    modded_values.sort_unstable_by_key(|item| item.id);
    vanilla_values.sort_unstable_by_key(|item| item.id);

    // check for duplicate Item id's per vec
    assert!(!modded_values.windows(2).any(|w| w[0].id == w[1].id));
    assert!(!vanilla_values.windows(2).any(|w| w[0].id == w[1].id));

    // check if any Item id is in both vecs
    // this is easily done by just combining the vecs and sorting again.
    let combined: &mut Vec<&Item> =
        &mut Vec::with_capacity(vanilla_values.len() + modded_values.len());
    combined.extend(&*vanilla_values); // how does dereferencing and borrowing again work here? Beats me.
    combined.extend(&*modded_values);
    // this should already be in order anyways, if all goes well.
    combined.sort_unstable_by_key(|item| item.id);
    assert!(!combined.windows(2).any(|w| w[0].id == w[1].id));

    // Check for duplicate Item names
    assert!(!combined.windows(2).any(|w| w[0].name == w[1].name));

    // We dont check for duplicate display names, since that is a normal thing to have.

    // check that the keys match the modded Item names.
    let modded_values_two = &MODDED_ITEMS;
    for (key, value) in modded_values_two.iter() {
        assert_eq!(key, &value.name)
    }
}
