// Turtle networking related tests.

use log::info;
use rand::Rng;

use crate::{minecraft::computercraft::computer_types::packet_types::{DebuggingPacket, RawTurtlePacket}, tests::prelude::*};

/// Spawns a tree_chop task test. This is it's own function to allow you to start
/// hella tree tests at once for fun!
async fn run_tree_chop(
    mut test: MinecraftTestHandle,
    mut position: MinecraftPosition,
) -> bool {
    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    -- This does not need to be accurate for this test, its all relative anyways.
    ---@type MinecraftPosition
    local start_position = {
        position = {
            x = 0,
            y = 0,
            z = 0
        },
        facing = "n"
    }

    -- Sync yield
    debugging.wait_step()

    -- Equip the axe
    turtle.equipRight()

    -- Move back to let the tree be placed
    turtle.back()

    -- Yield to let the test know we are ready to start
    debugging.wait_step()

    -- setup the OS
    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local tree_task = {
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        ---@type TreeChopTaskData
        task_data = {
            name = "tree_chop",
            timeout = 100,
            target_logs = 1,
            target_saplings = 1,
        },
    }

    -- Add the task to the queue
    mesh_os.testAddTask(tree_task)

    -- Wait for the go-ahead to start the task
    -- Run the task. this will throw when the queue is empty.
    local _, _ = pcall(mesh_os.main)

    -- Tell the os we are done.
    debugging.wait_step()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
        mesh_os: Some(true),
        debugging: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(2000)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    // Before turning on the turtle, give it an axe
    let gave_axe = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_axe").unwrap(), 1, 0)).await;
    assert!(gave_axe.success());

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the turtle to move backwards
    socket.receive(15).await.expect("Should receive");

    // Place the tree
    let t_p = position.with_offset(test.corner());
    #[allow(deprecated)] // like hell im making a tree command, TODO: replace this when we can place
    // schematics from files.
    test.command(TestCommand::RawCommand(&format!("/place feature minecraft:fancy_oak {} {} {}", t_p.position.x, t_p.position.y, t_p.position.z))).await;

    // Ready for the turtle to do the tree.
    socket.send(str.clone(), 5).await.expect("Should send");

    // This may take a while.
    socket.receive(840).await.expect("Should receive");

    // Turtle is done.
    // Did it end up back at the start?
    position.move_direction(MinecraftCardinalDirection::South);
    let turtle_back = test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("computercraft:turtle_normal").unwrap())).await.success();
    info!("Turtle made it back: {turtle_back}");

    // There should also NOT be an oak log in front of the turtle.
    position.move_direction(MinecraftCardinalDirection::North);
    let no_log = !test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("minecraft:oak_log").unwrap())).await.success();
    info!("There is no log in front of the turtle: {no_log}");

    let success = turtle_back && no_log;
    test.stop(success).await;

    success
}

/// Tries to chop down a big oak tree.
///
/// Considered successful if the turtle returns to the start point.
#[tokio::test]
async fn tree_chop_test() {
    // ts tree so chopped 💔
    let area = TestArea {
        size_x: 15,
        size_z: 15,
    };
    let test = MinecraftTestHandle::new(area, "tree_chop task test").await;
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 7, y: 1, z: 7 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let success = run_tree_chop(test, position).await;
    assert!(success);
}

/// Chop 100 trees at once. Skipped for hopefully obvious reasons. Its a stress test.
#[tokio::test]
#[ignore]
async fn tree_chop_galore() {
    let mut handles = vec![];

    for i in 0..100 {
        let handle = tokio::spawn(async move {
            let area = TestArea {
                size_x: 15,
                size_z: 15,
            };
            let test = MinecraftTestHandle::new(area, &format!("tree_chop task test {}", i)).await;
            let position = MinecraftPosition {
                position: CoordinatePosition { x: 7, y: 1, z: 7 },
                facing: Some(MinecraftCardinalDirection::North),
            };

            run_tree_chop(test, position).await
        });
        handles.push(handle);
    }

    // Wait for all the chops to finish
    let mut fails: usize = 0;
    let mut passes: usize = 0;
    for handle in handles {
        match handle.await {
            Ok(result) => {
                if result {
                    passes += 1;
                } else {
                    fails += 1;
                }
            }
            Err(e) => {
                fails += 1;
                info!("Failed to rejoin tree chop task??");
                info!("{e}");
            }
        }
    }
    let all_passed = fails == 0;
    info!("Ran {} tree tests. Of those tests, {} passed and {} failed.", fails + passes, passes, fails);
    assert!(all_passed, "One or more tree_chop tests failed");
}

/// Make sure recursive miner can actually count.
///
/// Mines a 3x3x3 cube of stone to check that, indeed, there was 27 stone mined.
#[tokio::test]
async fn recursive_miner_test() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };
    let mut test = MinecraftTestHandle::new(area, "recursive_miner counting test").await;
    let mut position = MinecraftPosition {
        position: CoordinatePosition { x: 2, y: 1, z: 2 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    -- This does not need to be accurate for this test, its all relative anyways.
    ---@type MinecraftPosition
    local start_position = {
        position = {
            x = 0,
            y = 0,
            z = 0
        },
        facing = "n"
    }

    -- Sync yield
    debugging.wait_step()

    -- Equip the pickaxe
    turtle.equipRight()

    -- Get out of the way
    turtle.back()
    turtle.back()

    -- Yield to let the test know we are ready to start
    debugging.wait_step()

    -- setup the OS
    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local miner_task = {
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        ---@type RecursiveMinerData
        task_data = {
            name = "recursive_miner",
            timeout = 60,
            mineable_groups = {
                {
                    names_patterns = {"minecraft:stone"},
                    tags = {}
                }
            },
            fuel_patterns = {},
        },
    }

    -- Add the task to the queue
    mesh_os.testAddTask(miner_task)

    -- Run the task. This will return the result of the task
    local _, result = pcall(mesh_os.main)

    local total_mined = result.result.total_blocks_mined or 0

    -- Send that back
    NETWORKING.debugSend(total_mined)

    -- Also send the amount of blocks broken of each category.
    -- the first and only group should have the same count as total blocks mined.
    local mined_blocks = result.result.mined_blocks.counts[1] or 0

    NETWORKING.debugSend(mined_blocks)
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
        mesh_os: Some(true),
        debugging: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(2000)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    // Give turt a pickaxe
    let gave_pickaxe = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_pickaxe").unwrap(), 1, 0)).await;
    assert!(gave_pickaxe.success());

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the turtle to move back twice
    socket.receive(15).await.expect("Should receive");



    // 3x3x3 stone cube
    let p1 = CoordinatePosition { x: 1, y: 1, z: 1 };
    let p2 = CoordinatePosition { x: 3, y: 3, z: 3 };
    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    assert!(test.command(TestCommand::Fill(p1, p2, &stone)).await.success());

    // Son, im mine 😭
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the mining to finish.
    let turtle_json = socket.receive(300).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    // This should just be a number
    let blocks_mined = debug_packet.inner_data.as_u64().unwrap();
    info!("Turtle claims to have mined {blocks_mined} blocks.");

    // Now get the count of the first group. It should be equal.
    let turtle_json = socket.receive(5).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let group_count = debug_packet.inner_data.as_u64().unwrap();
    info!("The group claims {group_count} blocks mined.");

    // Did the turtle return to start?
    position.move_direction(MinecraftCardinalDirection::South);
    position.move_direction(MinecraftCardinalDirection::South);
    let turtle_back = test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("computercraft:turtle_normal").unwrap())).await.success();
    info!("Did turtle make it back? : {turtle_back}");

    // All good?
    let winner_winner_chicken_dinner = blocks_mined == 27 && turtle_back && group_count == blocks_mined;

    test.stop(winner_winner_chicken_dinner).await;

    assert!(winner_winner_chicken_dinner)
}

/// Make sure branch mining doesn't fail
///
/// It should be able to find at least three pieces of the randomly placed copper ore.
#[tokio::test]
async fn branch_miner_test() {
    let area = TestArea {
        size_x: 19,
        size_z: 19,
    };

    let mut test = MinecraftTestHandle::new(area, "branch_miner test").await;

    // We spawn the turtle at the edge this time.
    // Still needs to be in the middle of the edge tho
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 9, y: 1, z: 18 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    -- This does not need to be accurate for this test, its all relative anyways.
    ---@type MinecraftPosition
    local start_position = {
        position = {
            x = 0,
            y = 0,
            z = 0
        },
        facing = "n"
    }

    -- Sync yield
    debugging.wait_step()

    -- Equip the pickaxe
    turtle.equipRight()

    -- Yield to let the test know we are ready to start
    debugging.wait_step()

    -- setup the OS
    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local miner_task = {
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        ---@type BranchMinerData
        task_data = {
            trunk_length = 17,
            name = "branch_miner",
            desired = {
                groups = {
                    {
                        desired_total = 3,
                        group = {
                            names_patterns = {
                                "copper_ore"
                            },
                            tags = {}
                        }
                    }
                }
            },
            discardables = { patterns = {} },
            fuel_items = { patterns = {} },
            incidental = {
                groups = {
                    {
                        names_patterns = { "stone" },
                        tags = {}
                    }
                }
            }
        },
    }

    -- Add the task to the queue
    mesh_os.testAddTask(miner_task)

    -- Run the task. This will return the result of the task
    local _, result = pcall(mesh_os.main)

    local total_mined = result.result.total_blocks_mined or -100

    -- Also send the amount of blocks broken of each category.
    -- the first and only group should have the same count as total blocks mined.
    local mined_blocks = result.result.mined_blocks.counts[1] or -100

    -- Send that back
    NETWORKING.debugSend(total_mined)
    NETWORKING.debugSend(mined_blocks)
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
        mesh_os: Some(true),
        debugging: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(2000)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    // Give turt a pickaxe
    let gave_pickaxe = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_pickaxe").unwrap(), 1, 0)).await;
    assert!(gave_pickaxe.success());

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the turtle to move back twice
    socket.receive(15).await.expect("Should receive");



    // Make a big stone platform
    // Do note that these positions are floating, this is intentional.
    let p1 = CoordinatePosition { x: 1, y: 2, z: 1 };
    let p2 = CoordinatePosition { x: 17, y: 2, z: 17 };
    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    assert!(test.command(TestCommand::Fill(p1, p2, &stone)).await.success());

    // Then disperse some ores in it
    // Luckily minecraft has a command for this
    // /place feature minecraft:ore_copper_large ~ ~ ~
    let x_offset = p1.with_offset(test.corner()).x + 1;
    let x_range = x_offset..x_offset + 17;
    let z_offset = p1.with_offset(test.corner()).z + 1;
    let z_range = z_offset..z_offset + 17;
    let y_level = p1.with_offset(test.corner()).y - 1;

    // This doesnt always work, so we do it a lot of times.
    let mut features_placed = 0;
    let mut rng = rand::rng();
    while features_placed <= 25 {
        let x_pos = rng.random_range(x_range.clone());
        let z_pos = rng.random_range(z_range.clone());
        // Run the command. We don't care about the result, but it should output SOMETHING
        let command = format!("/place feature minecraft:ore_copper_large {x_pos} {y_level} {z_pos}");
        #[allow(deprecated)] // hhhhh
        let command = test.command(TestCommand::RawCommand(&command));
        if !command.await.data().unwrap().contains("Failed") {
            // Feature placed!
            features_placed += 1
        }
    }

    // HOWEVER: minecraft is jank and the blocks wont show up until after a block
    // update, so after adding the ores, we have to clone the blocks back downwards
    // to make them show up properly.
    let p1_down = p1.with_offset(CoordinatePosition { x: 0, y: -1, z: 0 });

    let p1_string = p1.with_offset(test.corner()).as_command_string();
    let p2_string = p2.with_offset(test.corner()).as_command_string();
    let p1_down_string = p1_down.with_offset(test.corner()).as_command_string();

    let command_string = format!("/clone {p1_string} {p2_string} {p1_down_string} replace move");
    #[allow(deprecated)]
    let command = test.command(TestCommand::RawCommand(&command_string));
    let command_result = command.await.data();
    assert!(command_result.unwrap().contains("Succ"));

    // Slab has moved down, we can now start mining.
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the mining to finish.
    let turtle_json = socket.receive(300).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    // This should just be a number of ores mined.
    // This will panic if its -100, which is intended.
    let blocks_mined = debug_packet.inner_data.as_u64().unwrap();
    info!("Turtle claims to have mined {blocks_mined} total blocks.");

    // Now get the count of the first group. It should be equal.
    let turtle_json = socket.receive(5).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let copper_count = debug_packet.inner_data.as_u64().unwrap();
    info!("The turtle claims to have mined {copper_count} copper ore.");

    // Did the turtle return to start?
    let turtle_back = test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("computercraft:turtle_normal").unwrap())).await.success();
    info!("Did turtle make it back? : {turtle_back}");

    // All good?
    let winner_winner_chicken_dinner = blocks_mined > 0 && turtle_back && copper_count == 3;

    test.stop(winner_winner_chicken_dinner).await;

    assert!(winner_winner_chicken_dinner)
}

/// Craft some stuff! We're going to make a furnace and place it above ourselves.
#[tokio::test]
async fn crafting_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut test = MinecraftTestHandle::new(area, "crafting test").await;
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 1, y: 1, z: 1 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    -- position? who gaf
    ---@type MinecraftPosition
    local start_position = {
        position = {
            x = 0,
            y = 0,
            z = 0
        },
        facing = "n"
    }

    -- Sync yield
    debugging.wait_step()

    -- Signal ready to start
    debugging.wait_step()

    -- Equip the axe
    turtle.equipLeft()

    -- Setup mesh_os
    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local craft_task = {
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        ---@type CraftingData
        task_data = {
            name = "craft_task",
            recipe = {
                -- furnace
                shape = {
                    "cobblestone", "cobblestone", "cobblestone",
                    "cobblestone", "BLANK",        "cobblestone",
                    "cobblestone", "cobblestone", "cobblestone",
                }
            },
            count = 1,
        },
    }

    -- Add the task to the queue
    mesh_os.testAddTask(craft_task)

    -- Run the task
    local _, _ = pcall(mesh_os.main)

    -- Place the furnace (shoulda ended up in slot 1)
    turtle.placeUp()

    -- Tell the test we are done
    debugging.wait_step()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
        mesh_os: Some(true),
        debugging: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(2000)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    // Crafting table, cobblestone, chest, and an diamond axe to break the chest with.
    let axe = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_axe").unwrap(), 1, 0)).await;
    assert!(axe.success());
    let table = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("crafting_table").unwrap(), 1, 3)).await;
    assert!(table.success());
    let chest = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("chest").unwrap(), 1, 1)).await;
    assert!(chest.success());
    let cobblestone = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("cobblestone").unwrap(), 8, 2)).await;
    assert!(cobblestone.success());


    computer.turn_on(&mut test).await;

    let str = String::from("go");

    // Initial handshake
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Signal the turtle to begin the task
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Wait for the task to finish, which should also place the furnace.
    socket.receive(60).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Check that a furnace was placed above the turtle's starting position
    let furnace_pos = CoordinatePosition { x: position.position.x, y: position.position.y + 1, z: position.position.z };
    let got_furnace = test.command(TestCommand::TestForBlock(furnace_pos, &MinecraftBlock::from_string("minecraft:furnace").unwrap())).await.success();
    info!("Furnace placed above turtle: {got_furnace}");

    test.stop(got_furnace).await;
    assert!(got_furnace);
}