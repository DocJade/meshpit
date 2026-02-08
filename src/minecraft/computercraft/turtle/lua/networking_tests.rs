// Turtle networking related tests.

use log::info;
use crate::tests::prelude::*;

#[tokio::test]
/// Attempt basic ping pong over the websocket.
async fn websocket_ping_pong() {
    // create a test to run a 'puter in
    let area = TestArea {
        size_x: 3,
        size_z: 3,
    };
    let mut test = MinecraftTestHandle::new(area, "Websocket ping pong").await;
    // create a computer
    let position = MinecraftPosition {
        position: CoordinatePosition {
            x: 1,
            y: 1,
            z: 1,
        },
        facing: None,
    };

    // The file we will run at startup.
    let test_script = r#"
    local networking = require("networking")
    print("sending ping")
    networking.debugSend("ping")
    print("waiting for response")
    local ok, result = networking.waitForPacket(60)
    if not ok then
        print("no response")
        print(result)
        networking.debugSend("fail")
        -- skip shutting down to keep stuff on screen.
        goto cancel
    end
    print("got response")
    print("== response ==")
    print(result)
    print("== response ==")
    print("sending pass")
    networking.debugSend("pass")
    print("sending result")
    networking.debugSend(result)
    print("shutting down in 30 seconds.")
    os.sleep(30)
    os.shutdown()
    ::cancel::
    "#;

    let libraries = MeshpitLibraries {
        networking: Some(true),
        panic: Some(true),
        helpers: Some(true),
        ..Default::default()
    };

    let config = ComputerConfigs::StartupIncludingLibraries(test_script.to_string(), libraries);

    let setup = ComputerSetup::new(ComputerKind::Basic, config);
    let computer = test.build_computer(&position, setup).await;

    // Get ready for the websocket connection
    let mut socket = TestWebsocket::new(computer.id()).await;

    // Turn on the computer, and wait for the ping message
    computer.turn_on(&mut test).await;

    let ping = socket.receive().await;
    info!("Got ping!");
    info!("{ping}");
    assert!(ping.contains("ping"));

    // send back
    info!("Sending pong...");
    socket.send("\"pong\"".to_string()).await;
    info!("Sent.");

    // Wait for the next response
    info!("Awaiting response...");
    let response = socket.receive().await;
    let pass_fail = response.contains("pass");
    info!("Got it! {response}");
    info!("Pass fail? {pass_fail}");
    if pass_fail {
        info!("Pass!");
        // Get the next packet too
        info!("Waiting for followup packet...");
        let result = socket.receive().await;
        info!("Got it!");
        info!("{result}");
    } else {
        info!("fail!")
    }
    test.stop(pass_fail).await;
    assert!(pass_fail);
}