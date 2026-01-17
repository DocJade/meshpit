use std::{net::SocketAddrV4, process::Child};
use log::error;
use tokio::{net::TcpStream, sync::mpsc};
use tokio::net::TcpListener;

use crate::websocket::CCWebsocket;

/// Start the computercraft emulator and open a websocket to it.
/// 
/// Dropping the test handle will close the emulator.
/// Also returns the receiver for the computer.
pub async fn get_test_computer(config: TestEmulatorConfig) -> (TestHandle, mpsc::UnboundedReceiver<String>) {
    let child = get_test_emulator(&config);

    // if there is no incoming lua code, we wont be getting a stream... therefore we will not 
    // call that with no lua input.

    let stream = get_test_stream(&config).await;
    let tuple = CCWebsocket::new(stream.expect("Tests expect a websocket to open.")).await;
    let handle = TestHandle {
        process: ProcessGuard {child},
        websocket: tuple.0
    };
    (handle, tuple.1)
}

/// Start a socket-less computercraft emulator to test with.
/// 
/// This should be used to test things like mesh networking, since they cannot reach back out.
pub async fn get_socket_less_test_computer(config: TestEmulatorConfig) -> SocketLessTestHandle {
    let child = get_test_emulator(&config);
    SocketLessTestHandle {
        process: ProcessGuard {child},
    }
}

/// Start a Minecraft server and setup a turtle testing environment
pub fn get_test_turtle() -> ! {
    unimplemented!()
}

/// Spawn an emulator, requires a websocket, and an ID
/// 
/// Takes in a test emulator config, which contains the startup code for the bot.
fn get_test_emulator(config: &TestEmulatorConfig) -> Child {
    #[cfg(windows)]
    let process_command = std::process::Command::new("C:\\Program Files\\CraftOS-PC\\CraftOS-PC.exe");
    #[cfg(not(windows))]
    unimplemented!("TODO: test cases on other platforms lol");

    let mut cc_emulator = process_command;
    // set the lua code to run
    cc_emulator.arg("--exec").arg(&config.lua_code);
    // set the computercraft computer id
    cc_emulator.arg("--id").arg(config.id.to_string());
    
        
    cc_emulator.spawn().unwrap()
}

/// Get a stream for the test
async fn get_test_stream(config: &TestEmulatorConfig) -> Option<TcpStream> {
    let bind = TcpListener::bind(config.ip).await.unwrap();
    
    // Wait for a websocket connection, but time out just in case it never binds
    match tokio::time::timeout(std::time::Duration::from_millis(250), bind.accept()).await {
        Ok(Ok((stream, _))) => Some(stream),
        _ => None,
    }
}

pub struct TestHandle {
    pub process: ProcessGuard,
    pub websocket: CCWebsocket
}

pub struct SocketLessTestHandle {
    pub process: ProcessGuard,
    // pub websocket: CCWebsocket
}

pub struct ComputerPeripheralConfig {
    peripherals: Vec<(ComputerPeripheral, ComputerSide)>
}

pub struct ComputerPeripheral {
    peripheral: PeripheralType,
    side: ComputerSide
}

pub enum PeripheralType {
    Drive,
    WiredModem,
    WirelessModem,
    // Monitor,
    // Speaker,
    // Chest,
    Computer
}

pub enum ComputerSide {
    Top,
    Bottom,
    Left,
    Right,
    Front,
    Back,
}

impl std::fmt::Display for PeripheralType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PeripheralType::Drive => todo!(),
            PeripheralType::WiredModem => todo!(),
            PeripheralType::WirelessModem => todo!(),
            PeripheralType::Computer => todo!(),
        }
    }
}

impl std::fmt::Display for ComputerSide {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ComputerSide::Top => write!(f, "top"),
            ComputerSide::Bottom => write!(f, "bottom"),
            ComputerSide::Left => write!(f, "left"),
            ComputerSide::Right => write!(f, "right"),
            ComputerSide::Front => write!(f, "front"),
            ComputerSide::Back => write!(f, "back"),
        }
    }
}
pub struct ProcessGuard {
    pub child: Child
}

impl Drop for ProcessGuard {
    fn drop(&mut self) {
        // close the emulator, assuming it closed itself.
        #[allow(clippy::needless_late_init)] // todo: is this lint broken?
        let needs_closing: bool;
        match self.child.try_wait() {
            Ok(ok) => {
                needs_closing = ok.is_none();
            }, // closed right
            Err(_) => {
                needs_closing = true;
            },
        }

        if needs_closing {
            // child was not ready to close their lemonade stand, kill them
            match self.child.kill() {
                Ok(_) => (),
                Err(err) => {
                    // er...
                    error!("Couldn't kill the emulator!");
                    error!("{err}");
                    panic!("Failed to close emulator!")
                },
            };
        }
        
        
        // TODO: I'm pretty sure that dropping the CCWebsocket will properly close
        // the underlying channels and websockets for us.
    }
}

pub struct TestEmulatorConfig {
    id: u16,
    ip: SocketAddrV4,
    lua_code: String
}

impl TestEmulatorConfig {
    /// Make a new emulator
    /// 
    /// id is optional, if not provided, we default to 0.
    pub fn new(id: Option<u16>, ip: SocketAddrV4, lua_code: String) -> Self {
        let id_bind = id.unwrap_or_default();
        Self {
            id: id_bind,
            ip,
            lua_code
        }
    }
}