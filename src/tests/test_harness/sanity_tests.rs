// These tests are used to test the test harness itself to make sure it is working.

use std::time::Duration;

use crate::tests::prelude::*;

#[tokio::test]
#[ignore] // Only a sanity test. Doesn't always need to be ran.
/// Make a herobrine spawner
async fn basic_block_test() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };

    // gold base
    let base = TestCommand::Fill(
        CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        CoordinatePosition {
            x: 3,
            y: 1,
            z: 3, 
        },
        MinecraftBlock::from_string("gold_block").unwrap(),
    );

    // netherrack
    let rack = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 2,
                y: 2,
                z: 2, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("netherrack").unwrap(),
    );

    // fire
    let fire = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 2,
                y: 3,
                z: 2, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("fire").unwrap(),
    );

    // torch1
    let torch1 = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 1,
                y: 2,
                z: 2, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("redstone_torch").unwrap(),
    );
    // torch2
    let torch2 = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 2,
                y: 2,
                z: 1, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("redstone_torch").unwrap(),
    );
    // torch3
    let torch3 = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 3,
                y: 2,
                z: 2, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("redstone_torch").unwrap(),
    );
    // torch4
    let torch4 = TestCommand::SetBlock(
        MinecraftPosition {
            position: CoordinatePosition {
                x: 2,
                y: 2,
                z: 3, 
            },
            facing: None,
        },
        MinecraftBlock::from_string("redstone_torch").unwrap(),
    );

    let build_commands: Vec<TestCommand> = vec![base, rack, fire, torch1, torch2, torch3, torch4];

    let mut test = MinecraftTestHandle::new(area).await;

    // build the spawner
    for cmd in build_commands {
        assert!(test.command(cmd).await.success(), "Failed to place block!");
    }

    // Check that the fire ended up in the correct position.
    let fire_check = TestCommand::TestForBlock(
        CoordinatePosition {
            x: 2,
            y: 3,
            z: 2, 
        },
        MinecraftBlock::from_string("fire").unwrap(),
    );

    assert!(test.command(fire_check).await.success(), "Fire missing!");

    // if we made it here, the test has passed.
    test.stop(true).await;
}

#[tokio::test]
#[ignore] // This takes a while.
/// Place every block
async fn place_every_block() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };

    let mut test = MinecraftTestHandle::new(area).await;

    // Encase the test in barrier blocks so items dont fly everywhere
    let mut c1 = CoordinatePosition {
        x: 0,
        y: 1,
        z: 0, 
    };

    let mut c2 = CoordinatePosition {
        x: 4,
        y: 3,
        z: 4, 
    };

    assert!(
        TestCommand::Fill(c1, c2, MinecraftBlock::from_string("barrier").unwrap())
            .invoke(&mut test)
            .await
            .success()
    );

    // Make it hollow, otherwise items would still fly.
    c1.x += 1;
    c1.z += 1;
    c2.x -= 1;
    c2.y -= 1;
    c2.z -= 1;
    assert!(
        TestCommand::Fill(c1, c2, MinecraftBlock::from_string("air").unwrap())
            .invoke(&mut test)
            .await
            .success()
    );

    let block_pos = MinecraftPosition {
        position: CoordinatePosition {
            x: 2,
            y: 1,
            z: 2, 
        },
        facing: None,
    };
    let data = get_mc_data();

    assert!(data.blocks_by_name.keys().len() != 0);
    let mut failed: bool = false;
    let mut failed_block: String = "".to_string();
    for block in data.blocks_by_name.keys() {
        if !test
            .command(TestCommand::SetBlock(
                block_pos,
                MinecraftBlock::from_string(block).unwrap(),
            ))
            .await
            .success()
        {
            failed = true;
            failed_block = block.to_string();
            break;
        };
    }
    test.stop(!failed).await;
    if failed {
        panic!("Failed to place {failed_block} !")
    }
}

#[tokio::test]
/// Place a computer that does nothing.
async fn basic_computer_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut test = MinecraftTestHandle::new(area).await;

    // Place the computer in the test.
    // Computer position. The direction it faces does not matter for this test.
    let computer_position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: None,
    };

    let computer = ComputerSetup::new(
        ComputerKind::Basic,
        #[allow(deprecated)] // We are testing that building computers works.
        ComputerConfigs::Empty,
    );

    // Place the computer in the world
    let c = test.build_computer(&computer_position, computer).await;

    // command to check the state of the computer
    let is_on = TestCommand::GetBlockData(computer_position.position, "On".to_string());

    // Computer should be off before we start
    let is_this_thing_on = test.command(is_on.clone()).await.data().unwrap();
    assert!(
        is_this_thing_on.contains("0b"),
        "Computer was already on! Got: {is_this_thing_on}"
    );

    // Turn the computer on
    c.turn_on(&mut test).await;
    let result = test.command(is_on.clone()).await.data().unwrap();
    assert!(
        result.contains("1b"),
        "Computer didn't turn on! data: {result}"
    );

    // turn it back off
    c.turn_off(&mut test).await;
    let result = test.command(is_on.clone()).await.data().unwrap();
    assert!(
        result.contains("0b"),
        "Computer didn't turn off! data: {result}"
    );

    // if we made it here, the test has passed.
    test.stop(true).await;
}

#[tokio::test]
/// Place some turtles with fuel
async fn turtle_fuel_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut turtle_pos = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: None,
    };

    let mut test = MinecraftTestHandle::new(area).await;
    for turtle_number in 0..10u64 {
        let turtle_setup = ComputerSetup::new(
            ComputerKind::Turtle(Some(turtle_number * 2)),
            #[allow(deprecated)] // These turtles dont need to do anything.
            ComputerConfigs::Empty,
        );
        test.build_computer(&turtle_pos, turtle_setup).await;
        // make sure it got the correct amount of fuel
        let found: u64 = match TestCommand::GetBlockData(turtle_pos.position, "Fuel".to_string())
            .invoke(&mut test)
            .await
            .data()
            .unwrap_or(1234.to_string())
            .parse::<u64>()
        {
            Ok(ok) => ok,
            Err(_) => {
                test.stop(false).await;
                panic!("Failed to get fuel data of turtle {turtle_number}!")
            }
        };
        if found != turtle_number * 2 {
            test.stop(false).await;
            panic!(
                "Fuel value in turtle {turtle_number} did not match! Got {found}, expected {}!",
                turtle_number * 2
            );
        }
        // All good, next turtle.
        turtle_pos.position.y += 1;
    }
    // All good!
    test.stop(true).await;
}

#[tokio::test]
/// Test if we can set a startup file on a computer.
async fn test_startup() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let mut position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: None,
    };

    let mut test = MinecraftTestHandle::new(area).await;

    // This lua code when ran in a turtle will turn on the redstone output on the top of the computer
    let lua = "redstone.setOutput(\"top\", true)";
    let computer_setup = ComputerSetup::new(
        ComputerKind::Basic,
        ComputerConfigs::Startup(lua.to_string()),
    );

    // Place the computer
    let c = test.build_computer(&position, computer_setup).await;

    // Put a piston and sand on top of the computer, since we cant check the data on it... lol.
    position.position.y += 1;
    position.facing = Some(MinecraftFacingDirection::Up);
    if !TestCommand::SetBlock(position, MinecraftBlock::from_string("piston").unwrap())
        .invoke(&mut test)
        .await
        .success()
    {
        test.stop(false).await;
        panic!("Failed to place piston!")
    }

    position.position.y += 1;
    position.facing = None;
    let sand = MinecraftBlock::from_string("sand").unwrap();
    if !TestCommand::SetBlock(position, sand)
        .invoke(&mut test)
        .await
        .success()
    {
        test.stop(false).await;
        panic!("Failed to place sand!")
    }

    // Turn on the computer
    c.turn_on(&mut test).await;

    // wait a bit
    std::thread::sleep(Duration::from_secs(1));

    // The sand should have moved up.
    position.position.y += 1;
    if !TestCommand::TestForBlock(position.position, sand)
        .invoke(&mut test)
        .await
        .success()
    {
        test.stop(false).await;
        panic!("Sand did not move up!")
    }

    test.stop(true).await;
}
