// Stuff related to building test computers.

// Annoyingly, computers do not turn on and off instantly, and can take a weirdly long time. So we control a delay here.
pub(super) const COMPUTER_STATE_CHANGE_TIME: Duration = Duration::from_millis(1000);

use std::time::Duration;

use crate::tests::prelude::*;

// Do not derive on this. We do not want to be able to make copies of computers like this.
pub struct ComputerSetup {
    /// What kind of computer is this?
    pub(super) kind: ComputerKind,
    /// Which config to use when creating this computer
    pub(super) config: ComputerConfigs,
}

impl ComputerSetup {
    /// Make a new computer setup for a test
    pub fn new(kind: ComputerKind, config: ComputerConfigs) -> Self {
        Self { kind, config }
    }
}

// TODO: Use the same type as the computer kind we store in the database, whenever that is made.
#[derive(Clone, Copy)]
pub enum ComputerKind {
    /// Normal computer.
    Basic,
    /// A turtle. You may also set the starting fuel level of the turtle. Defaults to zero.
    ///
    /// Values higher than what a turtle can actually hold (20,000 on standard) will be automatically capped by computercraft.
    Turtle(Option<u64>),
}

impl From<ComputerKind> for MinecraftBlock {
    fn from(value: ComputerKind) -> Self {
        match value {
            ComputerKind::Basic => MinecraftBlock::from_string("computer_normal").unwrap(),
            ComputerKind::Turtle(_) => MinecraftBlock::from_string("turtle_normal").unwrap(),
        }
    }
}

#[derive(Clone)]
pub enum ComputerConfigs {
    /// Do not pre-setup this computer at all.
    ///
    /// You should not use this for building turtles/computers unless you have some spesific test to run,
    /// such as a turtle with no config that is already pre-fueled
    #[deprecated(note = "See value doc comment.")]
    Empty,
    // /// Opens a websocket on the computer, all data fed through this websocket will be ran as lua code.
    // ///
    // /// You should obtain this websocket instead of picking a number yourself. You have been warned.
    // Websocket(u16),
    /// Adds a `startup.lua` file to this computer with the contents of the incoming string.
    Startup(String),
}

// impl ComputerConfigs {
//     fn to_file(self) -> Vec<u8> {
//         match self {
//             ComputerConfigs::Empty => include_bytes!("../tests/startup_scripts/empty.lua").to_vec(),
//             ComputerConfigs::Websocket(socket) => {
//                 let file = include_str!("../tests/startup_scripts/eval_socket.lua");
//                 let mut fixed = file.replace("###URL###", "localhost"); //TODO: make the address configurable
//                 fixed = fixed.replace("###SOCKET###", &socket.to_string());
//                 fixed.as_bytes().into()
//             }
//         }
//     }
// }

// =========
// TestComputer
// =========

// The computer type that we actually let tests touch.
pub struct TestComputer {
    /// What's the ID of this computer?
    ///
    /// Quick note, it appears that computercraft does not recycle ID numbers.
    ///
    /// This is set automatically when they are placed in the world.
    ///
    /// This is not public, and is only used internally to start / stop computers.
    pub(super) id: u16,
    // We do not store anything about the type of this computer, where it is, how it was set up,
    // or anything of that sort, since we do not want tests to be able to query information about
    // these computers directly.
}

impl TestComputer {
    /// Turn on the computer. Does nothing if computer is already on.
    pub async fn turn_on(&self, handle: &mut MinecraftTestHandle) {
        // /computercraft turn-on 49
        #[allow(deprecated)] // we use the raw command here. yes that sucks.
        let command = TestCommand::RawCommand(format!("computercraft turn-on {}", self.id));
        let result = handle
            .command(command)
            .await
            .data()
            .expect("This should print");
        assert!(
            result.contains("Turned on"),
            "Missing turned on message! {result}"
        );

        // This takes a moment, so we must wait.
        std::thread::sleep(COMPUTER_STATE_CHANGE_TIME);
    }

    /// Turn off the computer. Does nothing if computer is already off.
    pub async fn turn_off(&self, handle: &mut MinecraftTestHandle) {
        // /computercraft shutdown 49
        #[allow(deprecated)] // we use the raw command here. yes that sucks.
        let command = TestCommand::RawCommand(format!("computercraft shutdown {}", self.id));
        let result = handle
            .command(command)
            .await
            .data()
            .expect("This should print");
        assert!(
            result.contains("Shutdown"),
            "Missing shutdown message! {result}"
        );
        std::thread::sleep(COMPUTER_STATE_CHANGE_TIME);
    }
}
