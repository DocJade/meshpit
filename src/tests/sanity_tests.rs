// very very basic tests to just see that the harness is working correctly

use std::time::Duration;

use crate::tests::test_harness::{
    ComputerConfigs, ComputerKind, ComputerSetup, MINECRAFT_TESTING_ENV, MinecraftFacingDirection,
    MinecraftPosition, MinecraftTest, TestArea, TestPassCondition, TestSetupCommand,
};

#[tokio::test]
/// Make a herobrine spawner
async fn basic_block_test() {
    let area = TestArea {
        size_x: 5,
        size_z: 5,
    };

    // gold base
    let base = TestSetupCommand::Fill(
        MinecraftPosition { x: 1, y: 1, z: 1 },
        MinecraftPosition { x: 3, y: 1, z: 3 },
        crate::tests::test_harness::MinecraftBlock::GoldBlock,
    );

    // netherrack
    let rack = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 2, y: 2, z: 2 },
        crate::tests::test_harness::MinecraftBlock::Netherrack,
    );

    // fire
    let fire = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 2, y: 3, z: 2 },
        crate::tests::test_harness::MinecraftBlock::Fire,
    );

    // torch1
    let torch1 = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 1, y: 2, z: 2 },
        crate::tests::test_harness::MinecraftBlock::RedstoneTorch,
    );
    // torch2
    let torch2 = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 2, y: 2, z: 1 },
        crate::tests::test_harness::MinecraftBlock::RedstoneTorch,
    );
    // torch3
    let torch3 = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 3, y: 2, z: 2 },
        crate::tests::test_harness::MinecraftBlock::RedstoneTorch,
    );
    // torch4
    let torch4 = TestSetupCommand::SetBlock(
        MinecraftPosition { x: 2, y: 2, z: 3 },
        crate::tests::test_harness::MinecraftBlock::RedstoneTorch,
    );

    let setup_commands: Vec<TestSetupCommand> =
        vec![base, rack, fire, torch1, torch2, torch3, torch4];

    let computers: Vec<ComputerSetup> = vec![];

    let passing_condition = TestPassCondition::Dummy;

    let timeout = Duration::from_secs(10);

    let test = MinecraftTest::new(area, setup_commands, computers, passing_condition, timeout);

    let result = MINECRAFT_TESTING_ENV.lock().unwrap().run(test).await;

    assert!(result)
}

#[tokio::test]
/// Place a computer that does nothing.
async fn basic_computer_test() {
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };

    let computer_position = MinecraftPosition { x: 1, y: 1, z: 1 };

    let computer = ComputerSetup::new(
        ComputerKind::Basic,
        ComputerConfigs::Empty,
        computer_position,
        MinecraftFacingDirection::North,
    );

    let setup_commands: Vec<TestSetupCommand> = vec![];

    let computers: Vec<ComputerSetup> = vec![computer];

    let passing_condition = TestPassCondition::Dummy;

    let timeout = Duration::from_secs(10);

    let test = MinecraftTest::new(area, setup_commands, computers, passing_condition, timeout);

    let result = MINECRAFT_TESTING_ENV.lock().unwrap().run(test).await;

    assert!(result)
}
