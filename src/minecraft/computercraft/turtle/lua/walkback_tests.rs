// Yes, we even test the lua.
// Since we have our own json serializer and de-serializer, its important to test these.

use log::info;

use crate::{minecraft::{computercraft::computer_types::{packet_types::{DebuggingPacket, RawTurtlePacket, WalkbackPacket}, walkback_type::Walkback}, peripherals::inventory::GenericInventory}, tests::prelude::*};

#[tokio::test]
/// Attempt the most bog-standard movement you've ever seen
async fn basic_movement_test() {

    // Turtle will: (with waits after every step)
    // pre-wait for the test to start
    // Step forward
    // Step 2 back
    // Step forward, turn left, step forward
    // 2 turn right, step 2 forward
    // back, up
    // down


    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };
    let mut test = MinecraftTestHandle::new(area, "Basic movement test").await;
    // create a computer
    let mut position = MinecraftPosition {
        position: CoordinatePosition {
            x: 3,
            y: 1,
            z: 3,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };
    
    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(5) then
            return
        end
        networking.debugSend("fail, no response from harness.")
        while true do end -- inf loop to time out the turtle.
    end

    walkback.setup(3,1,3,"n")
    wait_step()
    panic.assert(walkback.forward())
    wait_step()
    panic.assert(walkback.back())
    panic.assert(walkback.back())
    wait_step()
    panic.assert(walkback.forward())
    panic.assert(walkback.turnLeft())
    panic.assert(walkback.forward())
    wait_step()
    panic.assert(walkback.turnRight())
    panic.assert(walkback.turnRight())
    panic.assert(walkback.forward())
    panic.assert(walkback.forward())
    wait_step()
    panic.assert(walkback.back())
    panic.assert(walkback.up())
    wait_step()
    panic.assert(walkback.down())
    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    let air = MinecraftBlock::from_string("minecraft:air").unwrap();

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;

    // Forwards
    // Wait for turtle to finish moving
    let _ = socket.receive().await;
    // Check new position.
    position.move_direction(MinecraftCardinalDirection::North);
    // Make sure there is NOT air at the expected position
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    // Good, start next movement
    socket.send(str.clone()).await;
    
    let _ = socket.receive().await;
    position.move_direction(MinecraftCardinalDirection::South);
    position.move_direction(MinecraftCardinalDirection::South);
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    socket.send(str.clone()).await;
    
    let _ = socket.receive().await;
    position.move_direction(MinecraftCardinalDirection::North);
    position.move_direction(MinecraftCardinalDirection::West);
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    socket.send(str.clone()).await;
    
    let _ = socket.receive().await;
    position.move_direction(MinecraftCardinalDirection::East);
    position.move_direction(MinecraftCardinalDirection::East);
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    socket.send(str.clone()).await;
    
    let _ = socket.receive().await;
    position.move_direction(MinecraftCardinalDirection::West);
    position.move_direction(MinecraftCardinalDirection::Up);
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    socket.send(str.clone()).await;
    
    let _ = socket.receive().await;
    position.move_direction(MinecraftCardinalDirection::Down);
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    
    // All matched.
    test.stop(true).await
}

#[tokio::test]
/// Attempt to do some basic walkbacks.
async fn basic_walkback_tests() {
    // Turtle will: (with waits after every step)
    // pre-wait for the test to start
    // Move forwards twice, upwards twice, turn 180, move forwards once

    // this tests that the turtle can understand that walkbacks do not care
    // about rotation.

    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };
    let mut test = MinecraftTestHandle::new(area, "Basic walkback tests").await;
    // create a computer
    let mut position = MinecraftPosition {
        position: CoordinatePosition {
            x: 3,
            y: 1,
            z: 3,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };
    
    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(5) then
            return
        end
        networking.debugSend("fail, no response from harness.")
        while true do end -- inf loop to time out the turtle.
    end

    walkback.setup(3,1,3,"n")
    
    wait_step()
    panic.assert(walkback.forward())
    panic.assert(walkback.forward())
    panic.assert(walkback.up())
    panic.assert(walkback.up())
    panic.assert(walkback.turnRight())
    panic.assert(walkback.turnRight())
    panic.assert(walkback.forward())
    wait_step()
    panic.assert(walkback.rewind())

    
    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    let air = MinecraftBlock::from_string("minecraft:air").unwrap();

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;
    
    // Wait for walkback to hit end destination
    let _ = socket.receive().await;
    
    // Copy the moves locally.
    position.move_direction(MinecraftCardinalDirection::North);
    position.move_direction(MinecraftCardinalDirection::North);
    position.move_direction(MinecraftCardinalDirection::Up);
    position.move_direction(MinecraftCardinalDirection::Up);
    position.move_direction(MinecraftCardinalDirection::South);
    
    // Turtle actually made it there?
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());
    
    // Now let it walkback
    socket.send(str.clone()).await;
    
    // Wait for the rewind
    let _ = socket.receive().await;

    // Reset our position
    position.position = CoordinatePosition {
            x: 3,
            y: 1,
            z: 3,
    };

    // Did the rollback work?
    assert!(!test.command(TestCommand::TestForBlock(position.position, air)).await.success());

    // All good
    test.stop(true).await;

}

#[tokio::test]
/// Attempt to do some basic block detection and memorization.
async fn basic_block_memorization() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };
    let mut test = MinecraftTestHandle::new(area, "Basic seen memorization").await;

    let mut start_pos = MinecraftPosition {
        position: CoordinatePosition {
            x: 2,
            y: 1,
            z: 2,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };
    
    // Relative to the turtle
    let front_block_pos = CoordinatePosition { x: 1, y: 0, z: 0 };
    let up_block_pos = CoordinatePosition { x: 0, y: 1, z: 0 };

    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(5) then
            return
        end
        networking.debugSend("fail, no response from harness.")
        while true do end
    end
    walkback.setup(1,1,1,"n")
    -- handshake
    wait_step()

    -- inspect
    local _ = walkback.inspect()
    local _ = walkback.inspectUp()

    -- move away to ensure we aren't just re-reading it.
    panic.assert(walkback.back())

    -- check em
    local mem_front = walkback.blockQuery({x=1, y=1, z=0})
    local mem_up = walkback.blockQuery({x=1, y=2, z=1})

    -- report back
    networking.debugSend(mem_front)
    networking.debugSend(mem_up)
    
    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&start_pos, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    computer.turn_on(&mut test).await;

    // Ditch the facing direction for block placement
    start_pos.facing = None;

    // Place the blocks
    let stone = MinecraftBlock::from_string("stone").unwrap();
    let dirt = MinecraftBlock::from_string("dirt").unwrap();
    assert!(test.command(TestCommand::SetBlock(start_pos.with_offset(front_block_pos), stone)).await.success());
    assert!(test.command(TestCommand::SetBlock(start_pos.with_offset(up_block_pos), dirt)).await.success());

    // do the thing mr turtle pls
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;

    let front = socket.receive().await;
    let up = socket.receive().await;
    
    // make those blocks
    let front: RawTurtlePacket = serde_json::from_str(&front).unwrap();
    let front: DebuggingPacket = front.try_into().unwrap();
    let front: MinecraftBlock = serde_json::from_str(&front.debug_message).unwrap();
    let up: RawTurtlePacket = serde_json::from_str(&up).unwrap();
    let up: DebuggingPacket = up.try_into().unwrap();
    let up: MinecraftBlock = serde_json::from_str(&up.debug_message).unwrap();

    // Front is stone
    assert_eq!(front.get_full_name(), "minecraft:stone");

    // and dis mf got dirt on he head omegalul
    assert_eq!(up.get_full_name(), "minecraft:dirt");

    // all good
    test.stop(true).await;
}

#[tokio::test]
/// Attempt walkback deserialization
async fn walkback_serialization() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };
    let mut test = MinecraftTestHandle::new(area, "Walkback serialization").await;
    // create a computer
    let position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };
    
    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(5) then
            return
        end
        networking.debugSend("fail, no response from harness.")
        while true do end -- inf loop to time out the turtle.
    end

    walkback.setup(1,1,1,"n")
    
    wait_step()
    networking.debugSend(walkback.dataJson())
    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;

    // Store the json
    let json: String = socket.receive().await;

    // Deserialize it!
    let raw_packet: RawTurtlePacket = serde_json::from_str(&json).unwrap();
    let walkback_packet: WalkbackPacket = raw_packet.try_into().unwrap();
    let walkback: Walkback = walkback_packet.walkback;

    // The position should have not changed.
    assert_eq!(walkback.cur_position, position);
    
    test.stop(true).await;
}

#[tokio::test]
/// Attempt turtle inventory de-and-re-serialization
async fn empty_inventory_serialization() {
    // Yes the turtle has no items, but this is a sanity test.

    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };
    let mut test = MinecraftTestHandle::new(area, "Empty inventory serialization").await;
    // create a computer
    let position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };
    
    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(5) then
            return
        end
        networking.debugSend("fail, no response from harness.")
        while true do end -- inf loop to time out the turtle.
    end

    walkback.setup(1,1,1,"n")
    
    wait_step()
    networking.debugSend(walkback.inventoryJSON())
    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;

    // Store the json
    let json: String = socket.receive().await;

    // Deserialize it!
    let raw_packet: RawTurtlePacket = serde_json::from_str(&json).unwrap();
    let walkback_packet: DebuggingPacket = raw_packet.try_into().unwrap();
    let inventory: GenericInventory = serde_json::from_str(&walkback_packet.debug_message).unwrap();

    // Should have 16 slots
    assert_eq!(inventory.size, 16);
    assert_eq!(inventory.slots.len(), 16);

    // Every slot should be empty
    for slot in inventory.slots {
        assert!(slot.is_none())
    }
    
    test.stop(true).await;
}


#[tokio::test]
#[ignore]
/// Test that we can see every block and accurately report all of them back
async fn recognize_all_blocks() {
    // This is duplicated from the sanity test.
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };

    let mut test = MinecraftTestHandle::new(area, "Recognize all blocks").await;

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

    assert!(test.command(TestCommand::Fill(c1, c2, MinecraftBlock::from_string("barrier").unwrap())).await.success());

    // Make it hollow, otherwise items would still fly.
    c1.x += 1;
    c1.z += 1;
    c2.x -= 1;
    c2.y -= 1;
    c2.z -= 1;
    assert!(
        test.command(TestCommand::Fill(c1, c2, MinecraftBlock::from_string("air").unwrap())).await.success()
    );

    let mut block_pos = MinecraftPosition {
        position: CoordinatePosition {
            x: 2,
            y: 1,
            z: 2, 
        },
        facing: Some(MinecraftCardinalDirection::North),
    };

    // Create the turtle.

    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local networking = require("networking")
    local function wait_step()
        networking.debugSend("wait")
        if networking.waitForPacket(10) then
            return
        end
        -- Must be done.
        os.shutdown()
    end
    -- Store the position of the block
    local block_pos = {
        x = 2,
        y = 1,
        z = 2,
    }
    walkback.setup(2,1,2,"n")
    panic.assert(walkback.back())
    
    wait_step()
    while true do
        wait_step()
        local _ = walkback.inspect() -- Load the block
        -- Then actually get the full block info
        local block = walkback.blockQuery(block_pos, true)
        networking.debugSend(block)
    end
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&block_pos, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    // Remove the facing direction from the block placement so it doesn't explode
    block_pos.facing = None;

    computer.turn_on(&mut test).await;

    // Once the turtle messages down the socket, we know it's in position and we
    // can start the loop

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;
    
    let data = get_mc_data();
    
    assert!(data.blocks_by_name.keys().len() != 0);
    let mut failed: bool = false;
    let mut failed_block: String = "".to_string();
    for block in data.blocks_by_name.keys() {
        info!("Placing {block}");
        assert!(test.command(TestCommand::SetBlock(block_pos, MinecraftBlock::from_string(block).unwrap())).await.success());
        info!("Placed.");
        // Get the block from the turtle
        socket.send(str.clone()).await;
        let _ = socket.receive().await; // discard the wait message
        socket.send(str.clone()).await;
        let turtle_saw = socket.receive().await;
        let raw_packet: RawTurtlePacket = serde_json::from_str(&turtle_saw).expect("Turtle should return a packet.");
        let debug_packet: DebuggingPacket = raw_packet.try_into().expect("This should be a debugging packet.");
        
        // Now the inside of that packet is just a MinecraftBlock that needs to be deserialized.
        let returned_block: MinecraftBlock = serde_json::from_str(&debug_packet.debug_message).expect("This should be a block.");
        info!("Turtle saw: {}", returned_block.get_full_name());
        
        // Check that the block names are the same
        if returned_block.get_full_name() != *block {
            // Bad!
            failed = true;
            failed_block = block.to_string();
            break;
        }

        // Keep going!
        continue;
    }
    test.stop(!failed).await;
    if failed {
        panic!("Failed to recognize {failed_block} !")
    }
}

// #[tokio::test]
// /// Inventory slot swapping.
// async fn swapathon() {
//     // Just move the items between every slot in the inventory.
//     // TODO: we probably dont even need this.
// }

// #[tokio::test]
// /// Test that we can craft all items (this one might take a while)
// async fn craft_all_items() {
//     // TODO: Write this once we have a standardized way of sending
//     // recipes to the turtle
// }

// #[tokio::test]
// /// Test that walkback push-pop is working and working well at that, additionally
// /// attempt to force-load a walkback into the turtle for full manual control.
// async fn walkback_push_pop() {
//     //TODO: Actually test this...
// }

// #[tokio::test]
// /// Test walkbacks with extra jittery movement by doing 10 random moves then rolling back a single step 0-10 times,
// /// repeating until 1,000 steps have been taken, then rollback completely to the start position.
// async fn jitter_walk() {
//     // TODO: Only implement if we have issues with walkbacks in normal cases.
//     // I don't feel like writing this rn
// }

#[tokio::test]
/// Try querying previously seen positions.
async fn query_previous_positions() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };
    let mut test = MinecraftTestHandle::new(area, "Query previous positions").await;

    let position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: Some(MinecraftCardinalDirection::North),
    };

    let test_script = r#"
    local walkback = require("walkback")
    local panic = require("panic")
    local helpers = require("helpers")
    
    walkback.setup(1,1,1,"n")
    
    -- The positions to look at
    local pos1 = {x=1, y=1, z=1}
    local pos2 = {x=1, y=2, z=1}
    local pos3 = {x=1, y=3, z=1}
    local pos4 = {x=1, y=4, z=1}
    local nowhere = {x=1, y=4, z=1}

    -- their keys
    local key1 = helpers.keyFromTable(pos1)
    local key2 = helpers.keyFromTable(pos2)
    local key3 = helpers.keyFromTable(pos3)
    local key4 = helpers.keyFromTable(pos4)
    local zeros = helpers.keyFromTable(nowhere)

    -- Up 3 times, thus 4 visited positions
    panic.assert(walkback.up())
    panic.assert(walkback.up())
    panic.assert(walkback.up())

    -- Current chain should have all of the positions
    panic.assert(walkback.posQuery(key1, false))
    panic.assert(walkback.posQuery(key2, false))
    panic.assert(walkback.posQuery(key3, false))
    panic.assert(walkback.posQuery(key4, false))

    -- Go back down, which should trim old positions, and the only good one
    -- should be our current spot.
    panic.assert(walkback.down())
    panic.assert(walkback.down())
    panic.assert(walkback.down())

    -- current pos is good
    panic.assert(walkback.posQuery(key1, false))
    -- these shouldn't be there
    panic.assert(not walkback.posQuery(key2, false))
    panic.assert(not walkback.posQuery(key3, false))
    panic.assert(not walkback.posQuery(key4, false))

    -- with the full flag on, we should still be able to see those positions.
    panic.assert(walkback.posQuery(key1, true))
    panic.assert(walkback.posQuery(key2, true))
    panic.assert(walkback.posQuery(key3, true))
    panic.assert(walkback.posQuery(key4, true))

    -- we've never seen 0,0,0
    panic.assert(not walkback.posQuery(zeros, false))
    panic.assert(not walkback.posQuery(zeros, true))

    -- hard reset the walkback, now we shouldn't be able to see the old positions anymore.
    walkback.hardReset()
    panic.assert(not walkback.posQuery(key2, true))
    panic.assert(not walkback.posQuery(key3, true))
    panic.assert(not walkback.posQuery(key4, true))

    -- yell that everything worked
    networking.debugSend("all good mate")

    os.shutdown()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);
    let setup = ComputerSetup::new(ComputerKind::Turtle(Some(50)), config);
    let computer = test.build_computer(&position, setup).await;
    let mut socket = TestWebsocket::new(computer.id()).await;

    computer.turn_on(&mut test).await;

    // Initial handshake
    let str = String::from("go");
    let _ = socket.receive().await;
    socket.send(str.clone()).await;
    
    // wait for turtle to finish or error.
    let worked = socket.receive().await.contains("all good mate");
    test.stop(worked).await;
    assert!(worked)
}