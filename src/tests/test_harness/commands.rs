// Stuff related to running commands.

use crate::{
    minecraft::{types::MinecraftPosition, vanilla::block_type::MinecraftBlock},
    tests::test_harness::test_enviroment::{MINECRAFT_TESTING_ENV, MinecraftTestHandle},
};

/// Minecraft commands that tests are able to run.
///
/// All positions input into this command are interpreted as offsets from 0,0,0.
#[derive(Clone)]
pub enum TestCommand {
    /// Place a block.
    ///
    /// Returns a pass or fail.
    SetBlock(MinecraftPosition, MinecraftBlock),

    /// Fill some blocks.
    ///
    /// Returns a pass or fail.
    Fill(MinecraftPosition, MinecraftPosition, MinecraftBlock),

    /// Test for a block at some position.
    ///
    /// Returns a pass or fail.
    TestForBlock(MinecraftPosition, MinecraftBlock),

    /// Get data from a block entity at some position. Requires the path of the data.
    /// For example, you can get the fuel level of a turtle with "Fuel". Do note that
    /// an empty input string will return all blockdata.
    ///
    /// Returns Data, or None if no data was found, or no block was at that position.
    GetBlockData(MinecraftPosition, String),

    /// Run a raw command. You should not do this.
    #[doc(hidden)]
    #[deprecated(note = "I'm too lazy to refactor and make this private. Don't use.")]
    RawCommand(String),
}

impl TestCommand {
    /// Runs a supplied command. Returns a TestCommandResult
    pub(super) async fn invoke(&self, handle: &mut MinecraftTestHandle) -> TestCommandResult {
        // Get the environment so we can run commands
        let mut env = MINECRAFT_TESTING_ENV.lock().await;
        let corner = handle.corner();
        match self {
            TestCommand::SetBlock(minecraft_position, minecraft_block) => {
                let position = corner.with_offset(*minecraft_position).as_command_string();
                let block_string = minecraft_block.get_full_name();

                // Set the facing if needed.
                let face = if let Some(direction) = minecraft_position.facing {
                    format!("[facing={direction}]")
                } else {
                    "".to_string()
                };

                let result = env
                    .run_command(format!("setblock {position} {block_string}{face}"))
                    .await;
                // If we placed the block, we will get this text.
                TestCommandResult::Success(result.contains("Changed the block"))
            }
            TestCommand::Fill(pos1, pos2, minecraft_block) => {
                let position1 = corner.with_offset(*pos1).as_command_string();
                let position2 = corner.with_offset(*pos2).as_command_string();
                let block_string = minecraft_block.get_full_name();
                let result = env
                    .run_command(format!("fill {position1} {position2} {block_string}"))
                    .await;
                // Should fill
                TestCommandResult::Success(result.contains("Successfully filled"))
            }
            TestCommand::TestForBlock(minecraft_position, minecraft_block) => {
                // This command is less trivial.
                // To check if a block exists without replacing it, we need to use a execute command to test the block.
                // However, execute will not output anything, so we need to mark that the test passed or failed by placing
                // another block to test against. This time outside of the test.
                // Thus we use the block at the corner, offset -1 to move out of the test bounds, then fill that.
                let position_to_check = corner.with_offset(*minecraft_position).as_command_string();
                let marking_position = corner
                    .with_offset(MinecraftPosition {
                        x: -1,
                        y: 0,
                        z: -1,
                        facing: None,
                    })
                    .as_command_string();
                let check_block = minecraft_block.get_full_name();
                let marking_block = MinecraftBlock::from_string("bedrock")
                    .unwrap()
                    .get_full_name();

                // We will use the execute command to check the position for the block we want, and if it is there, we will place
                // the marking block.
                // execute if block ? ? ? (the block we're checking for) run setblock ? ? ? minecraft:bedrock
                let check_command = format!(
                    "execute if block {position_to_check} {check_block} run setblock {marking_position} {marking_block}"
                );

                // This will have no result.
                let _ = env.run_command(check_command).await;

                // Now we check for the marking block by trying to place a block there with `keep`, since its only allowed to replace air.
                // Thus if we are able to place the marking block there, it must have been air, and thus the marker block is missing.
                let mark_check_command: String =
                    format!("/setblock {marking_position} {marking_block} keep");

                let check_passed = env
                    .run_command(mark_check_command)
                    .await
                    .contains("Could not set the block");

                // now regardless if that block is there or not, clean up afterwards
                let _ = env
                    .run_command(format!("/setblock {marking_position} air"))
                    .await;

                TestCommandResult::Success(check_passed)
            }
            TestCommand::GetBlockData(minecraft_position, path) => {
                let position = corner.with_offset(*minecraft_position).as_command_string();
                let command_string = format!("/data get block {position} {path}");
                let result: String = env.run_command(command_string).await;

                // Could not get data?
                if !result.contains("has the following block data:") {
                    return TestCommandResult::Data(None);
                }

                // Remove the prefix.
                match result.split("has the following block data:").last() {
                    Some(string) => TestCommandResult::Data(Some(string.trim().to_string())),
                    None => TestCommandResult::Data(None),
                }
            }
            #[allow(deprecated)] // Yeah i know.
            TestCommand::RawCommand(command) => {
                // This is not very safe. but im not writing an interface for tons of commands.
                let result = env.run_command(command.to_string()).await;
                if result.is_empty() {
                    TestCommandResult::Data(None)
                } else {
                    TestCommandResult::Data(Some(result))
                }
            }
        }
    }
}

pub enum TestCommandResult {
    /// A pass/fail.
    Success(bool),
    /// Maybe some data.
    Data(Option<String>),
}

// we impl some casting methods to make tests less verbose
impl TestCommandResult {
    /// Extract the success bool. Panics if this is not a success variant.
    pub fn success(self) -> bool {
        match self {
            TestCommandResult::Success(result) => result,
            _ => panic!("Not a success variant!"),
        }
    }
    /// Extract the Data option. Panics if this is not a Data variant.
    pub fn data(self) -> Option<String> {
        match self {
            TestCommandResult::Data(data) => data,
            _ => panic!("Not a data variant!"),
        }
    }
}
