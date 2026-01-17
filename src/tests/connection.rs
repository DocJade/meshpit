// basic connection tests to the computercraft emulator.

use log::info;

use crate::tests::bridge::{MINECRAFT_ENV, MinecraftEnvironment};

#[cfg(test)]
#[ctor::ctor] // ctor forces this to run before everything else, so the logger outputs correctly. Yeah a bit heavy handed lol.
fn init_test_logging() {
    let _ = env_logger::builder()
        .is_test(true)
        .filter_level(log::LevelFilter::Info)
        .try_init();
}

#[cfg(test)]
#[ctor::dtor] // When all of the tests are over, we need to clean up (ie shut down) the minecraft server.
fn post_test_shutdown() {
    info!("Running post-test cleanup...");
    // function is async so we need another thread.
    let handle = std::thread::spawn(|| {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("Should be able to spawn a runtime for lazy making.");

        #[allow(clippy::await_holding_lock)] //TODO: idk what it wants, fix later
        rt.block_on(async {
            let mut guard = MINECRAFT_ENV
                .lock()
                .expect("We should have the only reference");
            let server: &mut MinecraftEnvironment = &mut guard;
            server.shutdown_and_wait().await;
        })
    });
    info!("Done cleaning up. Goodbye.");
}

#[tokio::test]
#[ntest::timeout(300_000)]
/// Basic test to see if the Minecraft server is actually running.
async fn test_start_server() {
    let mut guard = MINECRAFT_ENV
        .lock()
        .expect("We should have the only reference");
    let server: &mut MinecraftEnvironment = &mut guard;
    assert!(server.is_running());
}

#[tokio::test]
// #[ntest::timeout(1000)]
/// Test RCON functionality
async fn test_server_rcon() {
    let mut guard = MINECRAFT_ENV
        .lock()
        .expect("We should have the only reference");
    let server: &mut MinecraftEnvironment = &mut guard;

    // just try to get the world seed.
    let server_seed = server
        .send_rcon("/seed")
        .await
        .expect("rcon should not fail");
    info!("World seed is {server_seed}");
}

// TODO: basic computer networking test.

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
