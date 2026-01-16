// basic connection tests to the computercraft emulator.

use std::net::{Ipv4Addr, SocketAddrV4};
use crate::tests::test_common::{get_test_computer, TestEmulatorConfig};

#[tokio::test]
#[ntest::timeout(2000)]
/// Just try to start the emulator to make sure it exists at all.
async fn try_start_emulator() {
    // we assume that the address is localhost, bc yk, test.
    let addr = SocketAddrV4::new(Ipv4Addr::new(127, 0, 0, 1), 8080);
    // dont pass anything for the emulator to run, also use the default ID
    let config = TestEmulatorConfig::new(None, addr, SOCKET_TEMPLATE_LUA.to_string());
    let (handle, _) = get_test_computer(config).await;
    
    // with no lua, the bot wont close itself, so we will just kill the process.
    drop(handle)
}

#[tokio::test]
#[ntest::timeout(2000)]
/// Try a basic handshake with the emulator to make sure that networking is working.
async fn try_handshake() {
    
    // we assume that the address is localhost, bc yk, test.
    let addr = SocketAddrV4::new(Ipv4Addr::new(127, 0, 0, 1), 8080);
    // default ID
    let config = TestEmulatorConfig::new(None, addr, TEMP_TEST_SCRIPT.to_string());
    let (mut handle, mut incoming) = get_test_computer(config).await;
    let socket = &handle.websocket;
    let spawned = &mut handle.child_process;
    
    // get the hello
    let hello = incoming.recv().await.unwrap();
    assert_eq!(hello, "hello");
    
    // send da ack
    socket.send("ack".to_string()).unwrap();
    
    // we should hear an ack back before it closes.
    let ack = incoming.recv().await.unwrap();
    assert_eq!(ack, "ack");

    // wait for the cc emulator to die
    spawned.wait().unwrap();
}




const TEMP_TEST_SCRIPT: &str = r#"
local url = "ws://127.0.0.1:8080"
local ws, err = http.websocket(url)
if not ws then
    -- ded.
    os.shutdown()
end
ws.send("hello")
print("hello")
local string, boolean = ws.receive(5)
if not string then
-- failed to hear back from the websocket
os.shutdown()
end

if not string == "ack" then
-- didn't get the right thing back
os.shutdown()
end

ws.send("ack")
print("ack")
os.sleep(0.05)
ws.close()
os.shutdown()
"#;

// Just open and close the socket, for basic tests
const SOCKET_TEMPLATE_LUA: &str = r#"
local url = "ws://127.0.0.1:8080"
local ws, err = http.websocket(url)
if not ws then
    -- ded.
    os.shutdown()
end
os.sleep(0.05)
ws.close()
os.shutdown()
"#;