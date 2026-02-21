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

/// Make a lectern from scratch bc they're complicated as hell
#[tokio::test]
async fn lectern_from_scratch_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut test = MinecraftTestHandle::new(area, "lectern from scratch test").await;
    let position = MinecraftPosition {
        // placed mid-air so it doesn't have to move for the chest
        position: CoordinatePosition { x: 1, y: 2, z: 1 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    turtle.equipLeft()

    debugging.wait_step()

    mesh_os.startup(start_position)

    -- bc of task queuing these are in reverse order

    -- Lectern
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "slab", "slab", "slab",
                "BLANK", "bookshelf", "BLANK",
                "BLANK", "slab", "BLANK",
            }},
            count = 1,
        },
    })

    -- Bookshelf
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "planks", "planks", "planks",
                "book", "book", "book",
                "planks", "planks", "planks",
            }},
            count = 1,
        },
    })

    -- Slabs
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "planks", "planks", "planks",
                "BLANK", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }},
            count = 1,
        },
    })

    -- Books
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "paper", "paper", "BLANK",
                "paper", "leather", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }},
            count = 3,
        },
    })

    -- Paper
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "sugar_cane", "sugar_cane", "sugar_cane",
                "BLANK", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }},
            count = 3,
        },
    })

    -- Planks
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "oak_log", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }},
            count = 3,
        },
    })

    -- Leather. Making it from rabbit hide adds another step lol
    mesh_os.testAddTask({
        fuel_buffer = 0,
        return_to_facing = true,
        return_to_start = true,
        task_data = {
            name = "craft_task",
            recipe = { shape = {
                "rabbit_hide", "rabbit_hide", "BLANK",
                "rabbit_hide", "rabbit_hide", "BLANK",
                "BLANK", "BLANK", "BLANK",
            }},
            count = 3,
        },
    })

    -- Run all of those
    local _, _ = pcall(mesh_os.main)

    -- Place the lectern
    turtle.placeUp()

    -- Done
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

    // Give the turtle everything it needs to craft the lectern of doom and test-casery
    let axe = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_axe").unwrap(), 1, 0)).await;
    let table = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("crafting_table").unwrap(), 1, 1)).await;
    let chest = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("chest").unwrap(), 1, 2)).await;
    let hides = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("rabbit_hide").unwrap(), 12, 3)).await;
    let logs = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("oak_log").unwrap(), 3, 4)).await;
    let cane = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("sugar_cane").unwrap(), 9, 5)).await;
    assert!(axe.success() && table.success() && chest.success() && hides.success() && logs.success() && cane.success());

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    socket.receive(600).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Check for the lectern
    let lectern_pos = position.with_offset(CoordinatePosition { x: 0, y: 1, z: 0 }).position;

    let got_lectern = test.command(TestCommand::TestForBlock(
        lectern_pos,
        &MinecraftBlock::from_string("minecraft:lectern").unwrap(),
    )).await.success();
    info!("Lectern? : {got_lectern}");

    test.stop(got_lectern).await;
    assert!(got_lectern);
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

/// We will try to smelt 16 iron ore out of a stack of 64
#[tokio::test]
async fn smelting_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut test = MinecraftTestHandle::new(area, "smelting test").await;
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

    --- @type TaskDefinition
    local smelt_task = {
        fuel_buffer = 2,
        return_to_facing = true,
        return_to_start = true,
        --- @type SmeltingData
        task_data = {
            name = "smelt_task",
            to_smelt = {
                {
                    name_pattern = "raw_iron$",
                    limit = 16
                }
            },
            fuels = {
                "coal$"
            }
        }
    }

    -- Add the task to the queue
    mesh_os.testAddTask(smelt_task)

    -- Run the task
    local _, _ = pcall(mesh_os.main)

    -- Get another walkback to count how many iron ingots we ended up with
    local wb = require("walkback")

    local count = wb:inventoryCountPattern("ingot")

    -- Tell the test how many ingots we made.
    NETWORKING.debugSend(count)
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

    // Pickaxe, furnace, coal, and raw iron. I remember when you smelt the full blocks...
    let pick = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("diamond_pickaxe").unwrap(), 1, 0)).await;
    assert!(pick.success());
    let iron = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("raw_iron").unwrap(), 64, 1)).await;
    assert!(iron.success());
    let furnace = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("furnace").unwrap(), 1, 2)).await;
    assert!(furnace.success());
    let coal = test.command(TestCommand::InsertItem(position.position, &MinecraftItem::from_string("coal").unwrap(), 10, 3)).await;
    assert!(coal.success());

    computer.turn_on(&mut test).await;

    let str = String::from("go");

    // Initial handshake
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    // Signal the turtle to begin the task
    socket.receive(5).await.expect("Should receive");
    socket.send(str.clone(), 5).await.expect("Should send");

    let turtle_json = socket.receive(300).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let ingots = debug_packet.inner_data.as_u64().unwrap();
    info!("Turtle claims to have smelt {ingots} iron ingots.");

    test.stop(ingots == 16).await;
    assert!(ingots == 16);
}

/// Make sure the block_search task can actually find a block, in this case,
/// sand.
///
///
/// Surrounded in barriers to prevent the turtle from escaping.
#[tokio::test]
async fn block_search_task_test() {
    let area = TestArea {
        size_x: 13,
        size_z: 13,
    };

    let mut test = MinecraftTestHandle::new(area, "block_search task test").await;

    // Barrier box

    // Barriers
    let c_p1 = CoordinatePosition { x: 0, y: 1, z: 0 };
    let c_p2 = CoordinatePosition { x: 12, y: 3, z: 12 };
    let barrier = MinecraftBlock::from_string("barrier").unwrap();
    assert!(test.command(TestCommand::Fill(c_p1, c_p2, &barrier)).await.success());

    // Hollow it out
    let h_p1 = CoordinatePosition { x: 1, y: 1, z: 1 };
    let h_p2 = CoordinatePosition { x: 11, y: 2, z: 11 };
    let air = MinecraftBlock::from_string("air").unwrap();
    assert!(test.command(TestCommand::Fill(h_p1, h_p2, &air)).await.success());

    // Add some sand
    let s_p1 = CoordinatePosition { x: 9, y: 1, z: 9 };
    let s_p2 = CoordinatePosition { x: 11, y: 2, z: 11 };
    let sand = MinecraftBlock::from_string("minecraft:sand").unwrap();
    assert!(test.command(TestCommand::Fill(s_p1, s_p2, &sand)).await.success());

    // Turt
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 6, y: 1, z: 6 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local search_task = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        ---@type BlockSearchData
        task_data = {
            name = "block_search",
            to_find = {
                names_patterns = { "sand" },
                tags = {}
            },
        },
    }

    mesh_os.testAddTask(search_task)

    local _, result = pcall(mesh_os.main)

    -- Return a bool if we found the sand. This will crash the turtle if no
    -- sand is found somehow which is fine.
    local found = result.result.found ~= nil
    NETWORKING.debugSend(found)
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

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    // Sync
    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Wait for the search.
    let turtle_json = socket.receive(300).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let found_block = debug_packet.inner_data.as_bool().unwrap();
    info!("Turtle found sand: {found_block}");

    test.stop(found_block).await;
    assert!(found_block);
}

/// Trying the search in a real world i found out that er, the turtle will just
/// fly into the sky if it encounters an obstacle. New test for that.
///
/// Our first regression test 🥹 go white boy go
///
/// We use a vine as a canary to make sure it didn't fly too high.
#[tokio::test]
async fn block_search_no_fly_test() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };

    let mut test = MinecraftTestHandle::new(area, "block_search my people need me").await;

    let barrier = MinecraftBlock::from_string("barrier").unwrap();
    let air = MinecraftBlock::from_string("air").unwrap();

    // Barrier box

    // Barriers
    let c_p1 = CoordinatePosition { x: 0, y: 1, z: 0 };
    let c_p2 = CoordinatePosition { x: 4, y: 5, z: 4 };
    assert!(test.command(TestCommand::Fill(c_p1, c_p2, &barrier)).await.success());

    // Hollow it out
    let h_p1 = CoordinatePosition { x: 1, y: 1, z: 1 };
    let h_p2 = CoordinatePosition { x: 3, y: 4, z: 3 };
    assert!(test.command(TestCommand::Fill(h_p1, h_p2, &air)).await.success());

    // Stone block in the way that needs to be avoided
    let stone_pos = CoordinatePosition { x: 2, y: 1, z: 2 };
    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition { position: stone_pos, facing: None }, &stone)).await.success());

    // The humble goal sand
    let sand_pos = CoordinatePosition { x: 2, y: 1, z: 1 };
    let sand = MinecraftBlock::from_string("minecraft:sand").unwrap();
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition { position: sand_pos, facing: None }, &sand)).await.success());

    // Barrier for the vine to sit on
    let vine_attach_pos = CoordinatePosition { x: 1, y: 3, z: 3 };
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition { position: vine_attach_pos, facing: None }, &barrier)).await.success());

    // Apparently vines can be like, cubes? its odd.
    let vine_pos = CoordinatePosition { x: 2, y: 3, z: 3 };
    let vine = MinecraftBlock::from_string("minecraft:vine").unwrap();
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition { position: vine_pos, facing: None }, &vine)).await.success());

    // Turt
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 2, y: 1, z: 3 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local search_task = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        ---@type BlockSearchData
        task_data = {
            name = "block_search",
            to_find = {
                names_patterns = { "sand" },
                tags = {}
            },
        },
    }

    mesh_os.testAddTask(search_task)

    local _, result = pcall(mesh_os.main)

    local found = result.result.found ~= nil
    NETWORKING.debugSend(found)
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

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    // Sync
    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Wait for turtle to finish search'
    // Should be real fast
    let turtle_json = socket.receive(10).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let found_block = debug_packet.inner_data.as_bool().unwrap();
    info!("Turtle found sand: {found_block}");

    // Make sure the turtle didn't fly too high
    let vine_is_not_kil = test.command(TestCommand::TestForBlock(vine_pos, &vine)).await.success();
    info!("Turtle does not dream of space flight: {vine_is_not_kil}");

    let success = found_block && vine_is_not_kil;
    test.stop(success).await;
    assert!(found_block);
    assert!(vine_is_not_kil);
}

/// When doing a block search, the turtle can get stuck alternating between two
/// positions due to a hole. This is a regression test for that.
#[tokio::test]
async fn block_search_back_and_forth_test() {
    let area = TestArea {
        size_x: 6,
        size_z: 6,
    };

    let mut test = MinecraftTestHandle::new(area, "block_search stuck back and forth").await;

    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    let sand = MinecraftBlock::from_string("minecraft:sand").unwrap();

    // Wall in front
    // No fill bc lazy
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 1, z: 1 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 2, z: 1 }, facing: None}, &stone)).await.success());

    // Ceiling over hole
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 3, z: 2 }, facing: None}, &stone)).await.success());

    // Turtle starts on a stone block, has a stone block above it, and then
    // a sand on top of that for our goal.
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 1, z: 3 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 3, z: 3 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 4, z: 3 }, facing: None}, &sand)).await.success());

    // Start on the stone
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 2, y: 2, z: 3 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local search_task = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        ---@type BlockSearchData
        task_data = {
            name = "block_search",
            to_find = {
                names_patterns = { "sand" },
                tags = {}
            },
        },
    }

    mesh_os.testAddTask(search_task)

    local _, result = pcall(mesh_os.main)

    local found = result.result.found ~= nil
    NETWORKING.debugSend(found)
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
    // Only a little fuel since this should find the sand in 7 moves
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(10)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Should find it fast
    let turtle_json = socket.receive(30).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let found_block = debug_packet.inner_data.as_bool().unwrap();
    info!("Turtle found sand: {found_block}");

    // The turtle should end up next to the sand.
    let by_sand = CoordinatePosition { x: 2, y: 4, z: 4 };
    let turtle_block = MinecraftBlock::from_string("computercraft:turtle_normal").unwrap();
    let turtle_at_expected_pos = test
        .command(TestCommand::TestForBlock(by_sand, &turtle_block))
        .await
        .success();

    info!("Turtle in the right spot: {turtle_at_expected_pos}");

    let found_block = found_block && turtle_at_expected_pos;

    test.stop(found_block).await;
    assert!(found_block);
}


/// When searching for blocks the turtle can end up in a cycle of up, back, down,
/// forward, and repeat which gets it stuck.
#[tokio::test]
async fn block_search_4_step_loop() {
    let area = TestArea {
        size_x: 6,
        size_z: 6,
    };

    let mut test = MinecraftTestHandle::new(area, "block_search stuck back and forth").await;

    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    let sand = MinecraftBlock::from_string("minecraft:sand").unwrap();

    // Wall in front
    // No fill bc lazy
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 1, z: 1 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 2, z: 1 }, facing: None}, &stone)).await.success());

    // Ceiling over hole
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 3, z: 2 }, facing: None}, &stone)).await.success());

    // no need for the stone block below this time
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 3, z: 3 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 4, z: 3 }, facing: None}, &sand)).await.success());

    // Start on the floor
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 2, y: 1, z: 3 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local search_task = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        ---@type BlockSearchData
        task_data = {
            name = "block_search",
            to_find = {
                names_patterns = { "sand" },
                tags = {}
            },
        },
    }

    mesh_os.testAddTask(search_task)

    local _, result = pcall(mesh_os.main)

    local found = result.result.found ~= nil
    NETWORKING.debugSend(found)
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
    // Only a little fuel since this should find the sand in 6 moves
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(10)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Should find it fast
    let turtle_json = socket.receive(30).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let found_block = debug_packet.inner_data.as_bool().unwrap();
    info!("Turtle found sand: {found_block}");

    // The turtle should end up next to the sand.
    let by_sand = CoordinatePosition { x: 2, y: 4, z: 4 };
    let turtle_block = MinecraftBlock::from_string("computercraft:turtle_normal").unwrap();
    let turtle_at_expected_pos = test
        .command(TestCommand::TestForBlock(by_sand, &turtle_block))
        .await
        .success();

    info!("Turtle in the right spot: {turtle_at_expected_pos}");

    let found_block = found_block && turtle_at_expected_pos;

    test.stop(found_block).await;
    assert!(found_block);
}


/// Large overhangs can cause looping when moving down.
#[tokio::test]
async fn block_search_overhang() {
    let area = TestArea {
        size_x: 12,
        size_z: 12,
    };

    let mut test = MinecraftTestHandle::new(area, "block_search overhang").await;

    let stone = MinecraftBlock::from_string("minecraft:stone").unwrap();
    let sand = MinecraftBlock::from_string("minecraft:sand").unwrap();

    // Wall in front
    // No fill bc lazy
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 1, z: 1 }, facing: None}, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 2, z: 1 }, facing: None}, &stone)).await.success());

    // Ceiling over hole
    // longer ceiling with a required downwards movement at the end
    let p1 = CoordinatePosition { x: 2, y: 3, z: 2 };
    let p2 = CoordinatePosition { x: 2, y: 3, z: 9 };
    assert!(test.command(TestCommand::Fill(p1, p2, &stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 2, z: 9 }, facing: None}, &stone)).await.success());

    // Its okay that we have to move forwards for the sand again
    assert!(test.command(TestCommand::SetBlock(MinecraftPosition {position:CoordinatePosition { x: 2, y: 4, z: 3 }, facing: None}, &sand)).await.success());

    // Start on the floor
    let position = MinecraftPosition {
        position: CoordinatePosition { x: 2, y: 1, z: 3 },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local mesh_os = require("mesh_os")
    local panic = require("panic")
    require("networking")
    local debugging = require("debugging")

    ---@type MinecraftPosition
    local start_position = {
        position = { x = 0, y = 0, z = 0 },
        facing = "n"
    }

    debugging.wait_step()

    mesh_os.startup(start_position)

    ---@type TaskDefinition
    local search_task = {
        fuel_buffer = 0,
        return_to_facing = false,
        return_to_start = false,
        ---@type BlockSearchData
        task_data = {
            name = "block_search",
            to_find = {
                names_patterns = { "sand" },
                tags = {}
            },
        },
    }

    mesh_os.testAddTask(search_task)

    local _, result = pcall(mesh_os.main)

    local found = result.result.found ~= nil
    NETWORKING.debugSend(found)
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
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(100)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id())
        .await
        .expect("Should be able to get a websocket.");

    computer.turn_on(&mut test).await;

    let go = String::from("go");

    socket.receive(5).await.expect("Should receive");
    socket.send(go.clone(), 5).await.expect("Should send");

    // Should find it fast
    let turtle_json = socket.receive(120).await.expect("Should receive");
    let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_json).unwrap();
    let debug_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let found_block = debug_packet.inner_data.as_bool().unwrap();
    info!("Turtle found sand: {found_block}");

    // The turtle should end up next to the sand.
    let by_sand = CoordinatePosition { x: 2, y: 4, z: 4 };
    let turtle_block = MinecraftBlock::from_string("computercraft:turtle_normal").unwrap();
    let turtle_at_expected_pos = test
        .command(TestCommand::TestForBlock(by_sand, &turtle_block))
        .await
        .success();

    info!("Turtle in the right spot: {turtle_at_expected_pos}");

    let found_block = found_block && turtle_at_expected_pos;

    test.stop(found_block).await;
    assert!(found_block);
}