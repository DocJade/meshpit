// Stuff related to building test computers.

// Annoyingly, computers do not turn on and off instantly, and can take a weirdly long time. So we control a delay here.
pub(super) const COMPUTER_STATE_CHANGE_TIME: Duration = Duration::from_millis(1000);

use std::{path::PathBuf, time::Duration};
use walkdir::WalkDir;

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

/// Some libraries implicitly require other libraries. This will put the libraries into the turtle's storage,
/// but will not load them, you will still have to load them yourself.
///
/// You can create invalid combinations, and this is by design.
#[derive(Debug, Clone, Copy)]
pub struct MeshpitLibraries {
    /// Networking
    pub networking: Option<bool>,
    /// Walkback
    pub walkback: Option<bool>,
    /// The panic handler. You will not see any output without networking.
    pub panic: Option<bool>,
    /// Helpers.
    pub helpers: Option<bool>,
    /// Block
    pub block: Option<bool>,
    /// Item
    pub item: Option<bool>,
    /// Mesh OS
    ///
    /// This also comes with all of the tasks.
    pub mesh_os: Option<bool>,
}

impl MeshpitLibraries {
    /// Get a Vec containing all of the paths to the libraries.
    pub fn to_files(self) -> Vec<PathBuf> {
        let mut paths: Vec<PathBuf> = vec![];

        let lua_folder = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/minecraft/computercraft/turtle/lua");

        // Turtles always get the constants, as the file is quite small anyways.
        paths.push(lua_folder.join("constants.lua"));

        if self.networking.unwrap_or(false) {
            paths.push(lua_folder.join("networking.lua"));
        };
        if self.walkback.unwrap_or(false) {
            paths.push(lua_folder.join("walkback.lua"));
        };
        if self.panic.unwrap_or(false) {
            paths.push(lua_folder.join("panic.lua"));
        };
        if self.helpers.unwrap_or(false) {
            paths.push(lua_folder.join("helpers.lua"));
        };
        if self.block.unwrap_or(false) {
            paths.push(lua_folder.join("block.lua"));
        };
        if self.item.unwrap_or(false) {
            paths.push(lua_folder.join("item.lua"));
        };
        if self.mesh_os.unwrap_or(false) {
            paths.push(lua_folder.join("mesh_os.lua"));
            // Need to also grab all of the tasks.
            let task_folder = lua_folder.join("tasks");
            for entry in WalkDir::new(task_folder)
                .into_iter()
                .filter_map(|e| e.ok())
            {
                if entry.file_type().is_file() {
                    paths.push(entry.path().to_path_buf());
                }
            }
        };
        paths
    }

    pub fn new() -> Self {
        Self {
            networking: None,
            walkback: None,
            panic: None,
            helpers: None,
            block: None,
            item: None,
            mesh_os: None
        }
    }
}
impl Default for MeshpitLibraries {
    fn default() -> Self {
        Self::new()
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
    /// Adds a `startup.lua` file to this computer with the contents of the incoming string. This does
    /// not include any of the standard libraries that meshpit uses. Use StartupIncludingLibraries instead.
    Startup(String),
    /// Adds a `startup.lua` file to this computer, additionally including some meshpit libraries.
    StartupIncludingLibraries(String, MeshpitLibraries),
}

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
    /// This is not public, and is used internally to start / stop computers.
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
        let command = TestCommand::RawCommand(&format!("computercraft turn-on {}", self.id));
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
        tokio::time::sleep(COMPUTER_STATE_CHANGE_TIME).await;
    }

    /// Get the ID of the computer. You should avoid doing this unless you need it to keep tests agnostic.
    pub fn id(&self) -> u16 {
        self.id
    }

    /// Turn off the computer. Does nothing if computer is already off.
    pub async fn turn_off(&self, handle: &mut MinecraftTestHandle) {
        // /computercraft shutdown 49
        #[allow(deprecated)] // we use the raw command here. yes that sucks.
        let command = TestCommand::RawCommand(&format!("computercraft shutdown {}", self.id));
        let result = handle
            .command(command)
            .await
            .data()
            .expect("This should print");
        assert!(
            result.contains("Shutdown"),
            "Missing shutdown message! {result}"
        );
        tokio::time::sleep(COMPUTER_STATE_CHANGE_TIME).await;
    }
}
