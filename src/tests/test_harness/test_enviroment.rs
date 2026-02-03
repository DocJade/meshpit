// Testing galore

use crate::tests::{prelude::*, test_harness::computer_builder::COMPUTER_STATE_CHANGE_TIME};
use std::{cmp::max, sync::Arc};

use once_cell::sync::Lazy;
use tokio::sync::Mutex;

use crate::tests::bridge::MinecraftEnvironment;

pub struct MinecraftTestEnvironment {
    /// The Minecraft environment we're running in.
    pub environment: MinecraftEnvironment,
    /// Where the current offset of the test setup plots are
    next_plot_corner: MinecraftPosition,
    /// The highest z value we've seen, as to not crash into old tests.
    highest_z: i64,
}

// this is the minecraft instance that all of the tests will use, so we have to make it once and then hold it here, otherwise
// we would have to re-start the server for every test, and that would be stupid as hell.
// TODO: I think i can refactor this into that ctor startup block that sets up logging for tests.
pub static MINECRAFT_TESTING_ENV: Lazy<Arc<Mutex<MinecraftTestEnvironment>>> = Lazy::new(|| {
    let env = MinecraftTestEnvironment::setup();
    Arc::new(env.into())
});

impl MinecraftTestEnvironment {
    /// Make a new test environment.
    ///
    /// This references the normal Minecraft environment, so this gets built after the first environment builds.
    fn setup() -> Self {
        let handle = std::thread::spawn(|| {
            let rt = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("Should be able to spawn a runtime for lazy making.");

            rt.block_on(async { MinecraftEnvironment::start().await })
        });

        let environment = handle.join().expect("well crap");

        // Load and lock that global, its ours!
        Self {
            environment,
            // This does not need a facing direction.
            next_plot_corner: MinecraftPosition {
                x: 0,
                y: -60,
                z: 0,
                facing: None,
            },
            highest_z: 0,
        }
    }
}

/// A handle of a running test.
pub struct MinecraftTestHandle {
    /// The area that this test occupies, and the corner that the test is based on.
    ///
    /// Test areas start at the southeast corner position and grow from there. (towards positive x/z)
    ///
    /// This cannot be modified once the test has started, since we cannot re-allocate the plot we are running on.
    area: TestArea,

    /// The south-east corner of the test area. All coordinates used in tests are relative to this position.
    ///
    /// This cannot be modified once the test has started, since we cannot move our testing location.
    corner: MinecraftPosition,
}

impl MinecraftTestHandle {
    /// Create the testing plot for this test and return a test handle.
    ///
    /// Requires a test area, since we need to know how much space this test will use.
    pub async fn new(area: TestArea) -> Self {
        // Account for the area starting at "0" thus being 1 block bigger than expected.
        let area = TestArea {
            size_x: area.size_x - 1,
            size_z: area.size_x - 1,
        };

        // Get a copy of the environment
        let mut env = MINECRAFT_TESTING_ENV.lock().await;

        // Find our plot position
        let corner = env.get_test_position(area);

        // Force load the plot
        let c1 = corner;
        let offset = MinecraftPosition {
            x: area.size_x.into(),
            y: 0,
            z: area.size_z.into(),
            facing: None,
        };
        let c2 = corner.with_offset(offset);

        let command: String = format!("forceload add {} {} {} {}", c1.x, c1.z, c2.x, c2.z,);
        let _ = env.run_command(command).await; // we assume this works, also i dont wanna parse the output rn

        // Update the floor
        env.update_floor(
            corner,
            area,
            MinecraftBlock::from_string("yellow_concrete").unwrap(),
        )
        .await;

        Self { area, corner }
    }

    /// Run a test command.
    pub async fn command(&mut self, command: TestCommand) -> TestCommandResult {
        command.invoke(self).await
    }

    /// Get the area of the test
    pub fn area(&self) -> TestArea {
        self.area
    }

    /// Get the corner position of the test
    pub fn corner(&self) -> MinecraftPosition {
        self.corner
    }

    /// Finish the test and clean up. Requires a pass or fail status to update the plot floor.
    pub async fn stop(self, passed: bool) {
        let mut env = MINECRAFT_TESTING_ENV.lock().await;
        // Update floor
        let block = if passed {
            MinecraftBlock::from_string("lime_concrete").unwrap()
        } else {
            MinecraftBlock::from_string("red_concrete").unwrap()
        };

        env.update_floor(self.corner, self.area, block).await;
        // We do not stop force-loading the chunks, since another test could be contained within it.
        // If we had something else to clean here, we would. but we dont.
        // TODO: Turn off all the computers within this chunk if possible? Maybe replace their blocks if needed.
    }

    /// Create and initialize a computer within this test.
    /// This should only be used for test setup.
    ///
    /// You can create turtles normally via setblock or via placing them with other turtles. This method is for when you
    /// need to create a turtle that is already configured with some state. Such as being the first computer in an area, since you
    /// cannot configure a computer without another pre-existing computer.
    ///
    /// To prevent code-paths and tests being dependant on computer ID's, you are not allowed to use the resulting computer type
    /// to get any information about the computer.
    ///
    /// Returns a TestComputer.
    ///
    /// Takes the computer to build, and the position to build the computer at.
    pub async fn build_computer(
        &mut self,
        position: &MinecraftPosition,
        setup: ComputerSetup,
    ) -> TestComputer {
        // Place the computer and turn it on, then get it's ID.
        // We want to use the other methods as much as possible here so we don't have a bunch
        // of raw commands.
        let block: MinecraftBlock = setup.kind.into();
        assert!(
            TestCommand::SetBlock(*position, block)
                .invoke(self)
                .await
                .success()
        );

        // Don't forget to offset the position into the test we're in.
        let position_string = position.with_offset(self.corner()).as_command_string();

        // Turn on the computer. This is our only raw command.
        // /data modify block -2 -60 10 On set value 1b
        #[allow(deprecated)]
        // used to kickstart computers. We do not have a test command for setting data right now.
        let turn_on = TestCommand::RawCommand(format!(
            "/data modify block {position_string} On set value 1b"
        ));
        assert!(
            turn_on
                .invoke(self)
                .await
                .data()
                .unwrap()
                .contains("Modified block data of")
        );

        // wait for that to turn on, it can take a bit.
        std::thread::sleep(COMPUTER_STATE_CHANGE_TIME);

        // Now that the computer is on, we can get it's ID.
        // /data get block -2 -60 10 ComputerId
        let id: u16 = TestCommand::GetBlockData(*position, "ComputerId".to_string())
            .invoke(self)
            .await
            .data()
            .unwrap()
            .parse()
            .unwrap();

        // Now that we have the computers ID, we will turn it back off, then do whatever setup we need to do after this.
        // Since all we need is the ID to construct the final computer type, we'll do that now and use methods on it.
        let new_computer: TestComputer = TestComputer { id };

        new_computer.turn_off(self).await;

        // If this is a turtle and needs fuel, set it.
        if let ComputerKind::Turtle(amount) = setup.kind {
            let fuel = amount.unwrap_or(0);
            #[allow(deprecated)] // yes another raw command. TODO:!
            let refuel = TestCommand::RawCommand(format!(
                "/data modify block {position_string} Fuel set value {fuel}"
            ))
            .invoke(self)
            .await
            .data()
            .unwrap();
            // If the fuel value is what we want to set it to, thats fine as well.
            let assertion =
                refuel.contains("Modified block data of") || refuel.contains("Nothing changed.");
            assert!(assertion, "Failed to set fuel! Got: {refuel}");
        }

        // Update files if needed.
        match setup.config {
            #[allow(deprecated)] // we still need to match it
            ComputerConfigs::Empty => {
                /* nothing to do */
            }
            // ComputerConfigs::Websocket(port) => todo!(),
            ComputerConfigs::Startup(startup) => {
                add_file_to_computer(new_computer.id, startup, "startup.lua")
                    .await
                    .expect("Unable to write startup lua file.");
            }
            ComputerConfigs::StartupIncludingLibraries(startup, libraries) => {
                add_file_to_computer(new_computer.id, startup, "startup.lua")
                    .await
                    .expect("Unable to write startup lua file.");
                // Loop over he libraries and add them
                for path in libraries.to_files() {
                    let file_contents = std::fs::read_to_string(&path).expect("Unable to read lua file!");
                    let file_name = path.file_name().expect("Should have a file name").to_str().expect("Should be valid.");
                    add_file_to_computer(new_computer.id, file_contents, file_name).await.expect("Unable to write a lua file to the computer!");
                }
            }
        }

        // all done!
        new_computer
    }
}

/// Create a file on a computer.
/// 
/// Make sure to include the file extension if needed.
///
/// This function assumes the computer has already created its folder.
async fn add_file_to_computer<S: ToString + AsRef<[u8]>, P: AsRef<std::path::Path>>(
    id: u16,
    file_contents: S,
    file_name: P,
) -> Result<(), std::io::Error> {
    // Open the path for the computer folders.
    // Use a block here so we dont keep the env locked.
    let computer_directory = {
        let env = MINECRAFT_TESTING_ENV.lock().await;
        env.environment
            .get_server_folder()
            .join("world/computercraft/computer")
    };
    // We will re-create the folder structure just in case...
    let this_computer_dir = computer_directory.join(id.to_string());
    std::fs::create_dir_all(&this_computer_dir)?;

    // Write the file
    std::fs::write(this_computer_dir.join(file_name), file_contents)?;
    Ok(())
}

impl MinecraftTestEnvironment {
    /// Runs a minecraft command. Does not need a preceding slash.
    pub(super) async fn run_command(&mut self, command: String) -> String {
        self.environment
            .send_rcon(&command)
            .await
            .expect("Rcon should be open.")
    }

    /// Change the floor of a test
    async fn update_floor(
        &mut self,
        corner: MinecraftPosition,
        area: TestArea,
        floor_block: MinecraftBlock,
    ) {
        let p1 = corner.as_command_string();
        let p2 = MinecraftPosition {
            x: corner.x + i64::from(area.size_x),
            y: corner.y,
            z: corner.z + i64::from(area.size_z),
            facing: None,
        }
        .as_command_string();
        let block = floor_block.get_full_name();
        // run the fill command
        let command = format!("fill {p1} {p2} {block}");
        let result = self.environment.send_rcon(&command).await;
        if let Some(feedback) = result {
            if feedback.contains("is not loaded") {
                panic!("Tried to fill outside of loaded chunks!");
            }
            if feedback.contains("Too many blocks") {
                panic!("Floor for test is WAY too big!");
            }
        }
    }

    /// Get the next open test position
    fn get_test_position(&mut self, area: TestArea) -> MinecraftPosition {
        // we just give the current position, then we update our offsets afterwards
        // to pre-prepare for the next test
        let give_me = self.next_plot_corner;

        // Update the z gap if needed
        self.highest_z = max(self.highest_z, area.size_z.into());

        let test_gap: i64 = 4;

        // Set the corner of where the next plot will be
        // If the last test was over 100 blocks away from 0,0 on the x axis, we will
        // move to a new row of tests. since we wanna look at em :D

        let mut next_x: i64 = give_me.x;
        let mut next_z: i64 = give_me.z;

        if next_x >= 100 {
            // Shift down by the highest width seen, plus the gap
            next_z += self.highest_z + test_gap;

            // Reset the x position, and shift back since we always add the offset
            // regardless if we moved to a new row.
            next_x = 0 - test_gap - area.size_x as i64;

            // Reset the largest z we've seen
            self.highest_z = 0
        }

        // Increment to the next plot
        next_x += area.size_x as i64 + test_gap;
        let next: MinecraftPosition = MinecraftPosition {
            x: next_x,
            y: give_me.y, // the y position never changes.
            z: next_z,
            facing: None,
        };
        self.next_plot_corner = next;

        give_me
    }
}
