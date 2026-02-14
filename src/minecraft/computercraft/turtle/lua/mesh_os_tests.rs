// Turtle networking related tests.

use log::info;

use crate::tests::prelude::*;

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
    local function wait_step()
        NETWORKING.debugSend("wait")
        if NETWORKING.waitForPacket(240) then
            return
        end
        NETWORKING.debugSend("fail, no response from harness.")
        os.setComputerLabel("step failure")
    end

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
    wait_step()

    -- Equip the axe
    turtle.equipRight()

    -- Move back to let the tree be placed
    turtle.back()

    -- Yield to let the test know we are ready to start
    wait_step()

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
    local _, _ = pcall(mesh_os.main())

    -- Tell the os we are done.
    wait_step()
    "#;

    let libraries = MeshpitLibraries {
        walkback: Some(true),
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        block: Some(true),
        item: Some(true),
        mesh_os: Some(true)
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
    position.move_direction(MinecraftCardinalDirection::South);
    let turtle_back = test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("computercraft:turtle_normal").unwrap())).await.success();


    // There should also NOT be an oak log in front of the turtle.
    position.move_direction(MinecraftCardinalDirection::North);
    let no_log = !test.command(TestCommand::TestForBlock(position.position, &MinecraftBlock::from_string("minecraft:oak_log").unwrap())).await.success();

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
                if !result {
                    passes += 1;
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