// Testing galore

use std::{fmt::Display, sync::Arc, time::Duration};

use log::info;
use once_cell::sync::Lazy;

use crate::tests::bridge::MinecraftEnvironment;

pub struct MinecraftTestEnvironment {
    /// The Minecraft environment we're running in.
    pub environment: MinecraftEnvironment,
    /// Where the current offset of the test setup plots are
    next_plot_corner: MinecraftPosition,
}

// this is the minecraft instance that all of the tests will use, so we have to make it once and then hold it here, otherwise
// we would have to re-start the server for every test, and that would be stupid as hell.
// TODO: I think i can refactor this into that ctor startup block that sets up logging for tests.
pub static MINECRAFT_TESTING_ENV: Lazy<Arc<std::sync::Mutex<MinecraftTestEnvironment>>> =
    Lazy::new(|| {
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
            next_plot_corner: MinecraftPosition { x: 0, y: -60, z: 0 },
        }
    }
}

/// Struct that handles the bounding boxes and setup conditions of test cases.
pub struct MinecraftTest {
    /// The corner of this test's area. This will be set automatically as the test starts.
    corner: Option<MinecraftPosition>,
    /// How big the testing area needs to be
    area: TestArea,
    /// What commands to run before starting the test
    setup_commands: Vec<TestSetupCommand>,
    /// How to set up the computers in this test
    computers: Vec<ComputerSetup>,
    /// What condition must be met for the test to pass
    passing_condition: TestPassCondition,
    /// How long the test should run before timing out
    timeout: Duration,
}

impl MinecraftTest {
    /// Build a new test
    pub fn new(
        area: TestArea,
        setup_commands: Vec<TestSetupCommand>,
        computers: Vec<ComputerSetup>,
        passing_condition: TestPassCondition,
        timeout: Duration,
    ) -> Self {
        // The areas need to account for the edge blocks, without this adjustment a area of 5x5 would be 6x6.
        let fixed_area = TestArea {
            size_x: area.size_x - 1,
            size_z: area.size_x - 1,
        };
        Self {
            corner: None,
            area: fixed_area,
            setup_commands,
            computers,
            passing_condition,
            timeout,
        }
    }
}

/// The area that a test occupies. Will make a floor under the test of the size specified.
#[derive(Clone, Copy)]
pub struct TestArea {
    /// How many blocks long (east direction) this test needs
    pub size_x: u16,
    /// How many blocks wide (south direction) this test needs
    pub size_z: u16,
}

// TODO: this should not live in the test harness lmao
#[derive(Clone, Copy)]
pub struct MinecraftPosition {
    pub x: i64,
    pub y: i64,
    pub z: i64,
}

impl MinecraftPosition {
    /// Offset the position by an amount
    fn with_offset(&self, offset: MinecraftPosition) -> MinecraftPosition {
        Self {
            x: self.x + offset.x,
            y: self.y + offset.y,
            z: self.z + offset.z,
        }
    }
}

// TODO: this should not live in the test harness lmao
#[derive(Clone, Copy)]
pub enum MinecraftFacingDirection {
    North,
    East,
    South,
    West,
}
impl ToString for MinecraftFacingDirection {
    fn to_string(&self) -> String {
        match self {
            MinecraftFacingDirection::North => "north".to_string(),
            MinecraftFacingDirection::East => "east".to_string(),
            MinecraftFacingDirection::South => "south".to_string(),
            MinecraftFacingDirection::West => "west".to_string(),
        }
    }
}

/// A command that a test runs during setup.
/// All positions are relative to the test corner.
pub enum TestSetupCommand {
    /// Place a block.
    SetBlock(MinecraftPosition, MinecraftBlock),
    /// Fill some blocks.
    Fill(MinecraftPosition, MinecraftPosition, MinecraftBlock),
}

impl TestSetupCommand {
    /// Builds the command into a string
    fn build(&self, test: &MinecraftTest) -> String {
        let corner = test.corner.expect("Needs to be set by this point");
        match self {
            TestSetupCommand::SetBlock(minecraft_position, minecraft_block) => {
                // TODO: support facing directions. maybe facing should go into the MinecraftBlock?
                let position = corner.with_offset(*minecraft_position).as_command_string();
                let block_string = minecraft_block.to_string();
                format!("setblock {position} {block_string}")
            }
            TestSetupCommand::Fill(pos1, pos2, minecraft_block) => {
                let position1 = corner.with_offset(*pos1).as_command_string();
                let position2 = corner.with_offset(*pos2).as_command_string();
                let block_string = minecraft_block.to_string();
                format!("fill {position1} {position2} {block_string}")
            }
        }
    }
}

#[derive(Clone, Copy)]
pub struct ComputerSetup {
    /// What's the ID of this computer?
    ///
    /// This is set automatically when they are placed in the world.
    id: Option<u16>,
    /// What kind of computer is this?
    kind: ComputerKind,
    /// Which config to use when creating this computer
    config: ComputerConfigs,
    /// Relative position within the testcase
    offset: MinecraftPosition,
    /// Facing direction
    facing: MinecraftFacingDirection,
}

impl ComputerSetup {
    /// Make a new computer setup for a test
    pub fn new(
        kind: ComputerKind,
        config: ComputerConfigs,
        offset: MinecraftPosition,
        facing: MinecraftFacingDirection,
    ) -> Self {
        Self {
            id: None, // This will be set later.
            kind,
            config,
            offset,
            facing,
        }
    }
}

#[derive(Clone, Copy)]
pub enum ComputerKind {
    /// Normal computer.
    Basic,
    /// A turtle. Also configures the fuel it starts with
    Turtle(TurtleFuelSetup),
}

impl Into<MinecraftBlock> for ComputerKind {
    fn into(self) -> MinecraftBlock {
        match self {
            ComputerKind::Basic => MinecraftBlock::CCComputerNormal,
            ComputerKind::Turtle(_) => MinecraftBlock::CCTurtleNormal,
        }
    }
}
#[derive(Clone, Copy)]
pub enum TurtleFuelSetup {
    /// No fuel (you wont be able to move!)
    Empty,
    /// Gives the turtle one block of coal (800 fuel).
    ///
    /// Does not call turtle.refuel()
    Fueled,
}

#[derive(Clone, Copy)]
pub enum ComputerConfigs {
    /// Do not pre-setup this computer at all.
    Empty,
    /// Open a websocket and execute any lua code given
    Websocket(u16),
}

impl ComputerConfigs {
    fn to_file(self) -> Vec<u8> {
        match self {
            ComputerConfigs::Empty => {
                include_bytes!("../tests/startup_scripts/empty.lua").to_vec()
            },
            ComputerConfigs::Websocket(socket) => {
                let file = include_str!("../tests/startup_scripts/eval_socket.lua");
                let mut fixed = file.replace("###URL###", "localhost"); //TODO: make the address configurable
                fixed = fixed.replace("###SOCKET###", &socket.to_string());
                fixed.as_bytes().into()
            },
        }
    }
}

#[derive(Clone, Copy)]
pub enum TestPassCondition {
    //TODO: real conditions
    Dummy,
}

// TODO: this should not be in the test harness lmao
#[derive(Clone, Copy)]
pub enum MinecraftBlock {
    LimeConcrete,
    RedConcrete,
    YellowConcrete,
    Netherrack,
    GoldBlock,
    RedstoneTorch,
    Fire,
    CCComputerNormal,
    CCTurtleNormal,
}

// we can turn on turtles with nbt set commands
// /data modify block { coords } On set value 1b
// or computercraft commands
// /computercraft turn-on [computers...]

// get the ID of a turtle
// /data get block 1 -60 2 ComputerId

// make sure to always forceload the chunks that the test is in
// forceload add <from> [<to>]

// you can put items into turtles with hoppers

//TODO: test if the test escapes the boundaries of the test.

impl ToString for MinecraftBlock {
    fn to_string(&self) -> String {
        match self {
            MinecraftBlock::LimeConcrete => "minecraft:lime_concrete".to_string(),
            MinecraftBlock::RedConcrete => "minecraft:red_concrete".to_string(),
            MinecraftBlock::YellowConcrete => "minecraft:yellow_concrete".to_string(),
            MinecraftBlock::CCComputerNormal => "computercraft:computer_normal".to_string(),
            MinecraftBlock::CCTurtleNormal => "computercraft:turtle_normal".to_string(),
            MinecraftBlock::Netherrack => "minecraft:netherrack".to_string(),
            MinecraftBlock::GoldBlock => "minecraft:gold_block".to_string(),
            MinecraftBlock::RedstoneTorch => "minecraft:redstone_torch".to_string(),
            MinecraftBlock::Fire => "minecraft:fire".to_string(),
        }
    }
}

impl MinecraftPosition {
    /// Get the position as a string, used in commands (no commas)
    fn as_command_string(&self) -> String {
        format!("{} {} {}", self.x, self.y, self.z)
    }
}

impl MinecraftTestEnvironment {
    /// Run a test
    ///
    /// Returns a pass or fail.
    pub async fn run(&mut self, mut test: MinecraftTest) -> bool {
        // get the position we'll be running at
        let corner = self.get_test_position(&test);
        test.corner = Some(corner);

        // setup the ground for the test.
        // start as yellow, since test is running
        self.update_floor(&test, MinecraftBlock::YellowConcrete)
            .await;

        // run the startup commands
        for command in &test.setup_commands {
            // "well actually `/gamerule sendCommandFeedback false` doesn't return anything" die die die
            self.environment
                .send_rcon(&command.build(&test))
                .await
                .expect("Should run");
        }

        // setup the computers
        self.setup_computers(&mut test).await;

        // TODO: MAKE THIS ACTUALLY DO STUFF
        let test_passed = true;

        if test_passed {
            self.update_floor(&test, MinecraftBlock::LimeConcrete).await;
        } else {
            self.update_floor(&test, MinecraftBlock::RedConcrete).await;
        };

        test_passed
    }

    /// Build a computer within a test
    async fn setup_computers(&mut self, test: &mut MinecraftTest) {
        let computer_directory = self.environment.get_server_folder().join("world/computercraft/computer");
        for c in &mut test.computers {
            // TODO: refactor things into ComputerSetup

            // place the computer
            // /setblock { coords } computercraft:turtle_normal[facing=east]
            let computer_position = test
                .corner
                .expect("Should be set by now")
                .with_offset(c.offset);
            let computer_position_string = computer_position.as_command_string();
            let as_block: MinecraftBlock = c.kind.into();
            let computer_block = as_block.to_string();
            let facing = c.facing.to_string();
            let command =
                format!("setblock {computer_position_string} {computer_block}[facing={facing}]");
            let result = self
                .environment
                .send_rcon(&command)
                .await
                .expect("Should be able to place the computer");
            info!("{result}");

            // turn on the computer so it grabs an ID
            // /data modify block { coords } On set value 1b
            let command_2 = format!("data modify block {computer_position_string} On set value 1b");
            let result = self
                .environment
                .send_rcon(&command_2)
                .await
                .expect("Computer should be there");
            info!("{result}");

            // Get the ID of that new computer
            // /data get block { coords } ComputerId
            let command_3 = format!("data get block {computer_position_string} ComputerId");
            let result = self
                .environment
                .send_rcon(&command_3)
                .await
                .expect("Computer should be there");
            info!("{result}");
            let id: u16 = result
                .split(':')
                .next_back()
                .expect("Should be one, unless placing computer failed.")
                .trim()
                .parse()
                .expect("Should fit.");

            // and turn the computer off again. lol.
            // setting the block data here does not actually turn off the computer, so we have to use the
            // comptuercraft command instead. 
            // /computercraft shutdown 0  
            let command_4 = format!("computercraft shutdown {id}");
            let result = self
                .environment
                .send_rcon(&command_4)
                .await
                .expect("Computer should be there");
            info!("{result}");

            // update the id
            c.id = Some(id);

            // if this is a turtle that wants fuel, put it in.
            // TODO: PLEASE PULL THIS INTO ITS OWN THING I BEG
            match &c.kind {
                ComputerKind::Turtle(fuel) => {
                    match fuel {
                        TurtleFuelSetup::Empty => { /* nothing to do */ }
                        TurtleFuelSetup::Fueled => {
                            // place a hopper above the turtle
                            let up_one = MinecraftPosition { x: 0, y: 1, z: 0 };
                            let offset_1 = computer_position.with_offset(up_one);
                            let offset_2 = offset_1.with_offset(up_one);

                            let place_hopper = format!(
                                "setblock {} minecraft:hopper",
                                offset_1.as_command_string()
                            );
                            let result = self.environment.send_rcon(&place_hopper).await.unwrap();
                            info!("{result}");

                            // now spawn the coal item lol
                            // /summon item { coords } {Item:{id:coal_block,count:1,components:{}}}
                            let spawn_coal = format!(
                                "summon item {} {{Item:{{id:coal_block,count:1,components:{{}}}}}}",
                                offset_2.as_command_string()
                            );
                            let result = self.environment.send_rcon(&spawn_coal).await.unwrap();
                            info!("{result}");

                            // wait for the coal to go in
                            std::thread::sleep(Duration::from_secs(1));

                            // goodbye hopper
                            let murder =
                                format!("setblock {} minecraft:air", offset_1.as_command_string());
                            let result = self.environment.send_rcon(&murder).await.unwrap();
                            info!("{result}");
                        }
                    }
                }
                _ => { /* doesn't need anything else done */ }
            }

            // Now set up the lua it runs
            // make the folder for the computer
            let this_computer_dir = computer_directory.join(id.to_string());
            std::fs::create_dir_all(&this_computer_dir).unwrap();
            std::fs::write(this_computer_dir.join("startup.lua"), c.config.to_file()).unwrap();

            // all done making the computer :D
        }
    }

    /// Change the floor of a test
    async fn update_floor(&mut self, test: &MinecraftTest, floor_block: MinecraftBlock) {
        let corner = test.corner.expect("Should have the corner set by now.");
        let p1 = corner.as_command_string();
        let p2 = MinecraftPosition {
            x: corner.x + i64::from(test.area.size_x),
            y: corner.y,
            z: corner.z + i64::from(test.area.size_z),
        }
        .as_command_string();
        let block = floor_block.to_string();
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
    fn get_test_position(&mut self, test: &MinecraftTest) -> MinecraftPosition {
        // we just give the current position, then we update our offsets afterwards
        // to pre-prepare for the next test
        let give_me = self.next_plot_corner;

        // update the bounds
        let next = MinecraftPosition {
            x: give_me.x + i64::from(test.area.size_x) + 4, // gap between each test
            y: give_me.y,
            z: give_me.z, // we just move along x.
        };
        self.next_plot_corner = next;
        give_me
    }
}
