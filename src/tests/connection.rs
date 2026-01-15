// basic connection tests to the computercraft emulator.

use std::time::Duration;

use crate::websocket::CCWebsocket;
use tokio::{net::{TcpListener, TcpStream}, sync::mpsc};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{SinkExt, StreamExt};



#[tokio::test]
async fn try_start_emulator() {

    // TODO: this stinky, clean

    #[cfg(not(windows))]
    panic!("todo, this test needs to work on other platforms.");
    // really need a dedicated test harness / starter.

    // bind localhost
    let address = "127.0.0.1:8080";

    let bind = TcpListener::bind(address).await.unwrap();

    // start craftos emulator
    let mut process_command = std::process::Command::new("C:\\Program Files\\CraftOS-PC\\CraftOS-PC.exe");
    let mut cc_emulator = process_command
        .arg("--exec")
        .arg(TEMP_TEST_SCRIPT);




    let mut spawned = cc_emulator.spawn().unwrap();
        

    // wait for computercraft to start and open the websocket
    std::thread::sleep(Duration::from_millis(16));
    
    // accept the stream from the emulator
    let (stream, _) = bind.accept().await.unwrap();
    
    let (socket, mut incoming) = CCWebsocket::new(stream).await;
    
    // get the hello
    let hello = incoming.recv().await.unwrap();
    
    assert_eq!(hello, "hello");
    
    // send da ack
    socket.send("ack".to_string()).unwrap();
    std::thread::sleep(Duration::from_millis(16));
    
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