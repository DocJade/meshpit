// We need to run tests on the computers in ways that need to be fed or return some data.

// TODO: This implementation might just end up being what we do for the actual server, and
// thus will need to be moved out of here.

use std::{
    sync::{Arc, OnceLock},
    time::Duration,
};

use dashmap::DashMap;
use futures_util::{SinkExt, StreamExt};
use log::{info, warn};
use tokio::{
    net::TcpListener,
    sync::{OnceCell, mpsc},
};
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};

use crate::tests::prelude::MINECRAFT_TESTING_ENV;

// We force move the websocket to another thread, otherwise it would close between tests.
static WEBSOCKET_RUNNING: OnceCell<()> = OnceCell::const_new();
static GLOBAL_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

async fn run_websocket() {
    WEBSOCKET_RUNNING
        .get_or_init(|| async {
            // Move to another runtime so it lives forever!!!!!!
            let rt = GLOBAL_RUNTIME.get_or_init(|| {
                tokio::runtime::Builder::new_multi_thread()
                    .enable_all()
                    .build()
                    .expect("global runtime ded")
            });

            // run the server on that new perma thread
            rt.spawn(async move { run_test_websocket_server().await });

            // Wait a bit for it to bind.
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

            // Wait until the minecraft server is also running. This will prevent
            // tests from timing out on websocket requests regardless of how long
            // it might take the server to start.
            let lock = MINECRAFT_TESTING_ENV.lock().await;
            // Make sure the server actually started.
            assert!(lock.environment.is_running());
        })
        .await;
}

/// A websocket that can send/receive to a computer.
///
/// Having a test websocket does not guarantee that you will ever get a response.
pub struct TestWebsocket {
    /// The ID of the computer this websocket is tied to.
    id: u16,
    sender: mpsc::Sender<String>,
    receiver: mpsc::Receiver<String>,
}

#[derive(Debug)]
pub enum TestWebsocketError {
    AlreadyTaken,
    TimedOut,
    Closed,
}

// Tests need to eventually time out, thus recv() and send() must have a timeout.
impl TestWebsocket {
    /// Sent a message down the websocket
    #[must_use = "You really should check if that worked."]
    pub async fn send(
        &mut self,
        message: String,
        sec_timeout: u64,
    ) -> Result<(), TestWebsocketError> {
        let sent = self
            .sender
            .send_timeout(message, Duration::from_secs(sec_timeout))
            .await;
        match sent {
            Ok(_) => Ok(()),
            Err(err) => match err {
                mpsc::error::SendTimeoutError::Timeout(_) => Err(TestWebsocketError::TimedOut),
                mpsc::error::SendTimeoutError::Closed(_) => Err(TestWebsocketError::Closed),
            },
        }
    }

    /// Receive a message from the websocket
    #[must_use = "You really should check if that worked."]
    pub async fn receive(&mut self, sec_timeout: u64) -> Result<String, TestWebsocketError> {
        let hang = async {
            let got = self.receiver.recv().await;
            match got {
                Some(ok) => {
                    // TODO: TEMP
                    info!("{}", ok);
                    Ok(ok)
                }
                None => Err(TestWebsocketError::Closed),
            }
        };

        // run the send
        let sending = tokio::time::timeout(Duration::from_secs(sec_timeout), hang).await;
        match sending {
            Ok(ok) => ok,
            Err(_) => Err(TestWebsocketError::TimedOut),
        }
    }
}

/// Internal storage for our websockets.
struct ComputerChannel {
    to_test: mpsc::Sender<String>,
    from_test: mpsc::Receiver<String>,
}

// We store all of the connections to the individual turtles in this dashmap.
type Registry = Arc<DashMap<u16, ComputerChannel>>;
static REGISTRY: OnceLock<Registry> = OnceLock::new();

fn get_registry() -> &'static Registry {
    REGISTRY.get_or_init(|| Arc::new(DashMap::new()))
}

/// Run the websocket.
async fn run_test_websocket_server() {
    // This is currently hardcoded.
    let address = "localhost:4816";
    let listener = TcpListener::bind(address)
        .await
        .expect("Failed to bind for websocket!");

    while let Ok((stream, _socket_addr)) = listener.accept().await {
        tokio::spawn(async move {
            let mut computer_id = None;

            // We need a callback so we can get the computer ID header on the handshake
            // No idea how this works.
            // TODO: Make this deny requests instead of panicking if its missing the computer ID? Better connection handshake?
            let callback = |req: &Request, mut response: Response| {
                // Pull out the computer ID if it exists.
                if req.uri().path() != "/meshpit" {
                    warn!("Tried to connect at the non-meshpit uri! {req:#?}");
                    return Err(Response::builder()
                        .status(404)
                        .body(Some("Invalid Path".into()))
                        .unwrap());
                }
                // set protocol headers TODO: do we really need this
                if let Some(sub) = req.headers().get("Sec-WebSocket-Protocol") {
                    response
                        .headers_mut()
                        .insert("Sec-WebSocket-Protocol", sub.clone());
                }

                if let Some(id) = req.headers().get("Computer-ID") {
                    computer_id = Some(id.to_str().unwrap().parse::<u16>().unwrap());
                } else {
                    // No computer id header.
                    return Err(Response::builder()
                        .status(400)
                        .body(Some("Missing headers".into()))
                        .unwrap());
                }

                Ok(response)
            };

            let websocket_stream = match tokio_tungstenite::accept_hdr_async(stream, callback).await
            {
                Ok(ok) => ok,
                Err(err) => panic!("Failed to accept websocket! {err:#?}"),
            };

            let Some(id) = computer_id else {
                // no id was given.
                panic!("Got websocket handshake request that did not contain a computer ID!")
            };

            // Get the waiting handle in the registry. If nobody is waiting on this ID then we discard everything.
            // TODO: when merging into final implementation, we need to accept all connections regardless if they
            // are expected or not, and funnel them into some handler for all packets.
            let Some((_, mut broker)) = get_registry().remove(&id) else {
                // return; // Nobody has a handle to this computer so the computer cannot connect.
                // Usually happens when tests fail but turtles try to re-connect afterwards. So we ignore it.
                warn!("Computer {id} tried to connect, but nobody had a handle open!");
                return;
            };

            // split the socket so we can spawn the threads for the channels
            let (mut websocket_sender, mut websocket_receiver) = websocket_stream.split();

            // Computer -> Server
            let incoming = tokio::spawn(async move {
                while let Some(Ok(message)) = websocket_receiver.next().await {
                    if let Ok(text) = message.into_text() {
                        // close the socket if the person on the other side of the channel is gone.
                        // TODO: Performance: This makes heap allocated strings. This is slow. This will need to be swapped
                        // to some other format.
                        if broker
                            .to_test
                            .send(text.as_str().to_string())
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                }
            });

            // Server -> Computer
            let outgoing = tokio::spawn(async move {
                while let Some(message) = broker.from_test.recv().await {
                    // Close the socket if the computer doesn't accept the message.
                    if websocket_sender.send(message.into()).await.is_err() {
                        break;
                    }
                }
            });

            // Now wait for either side to close.
            tokio::select! {
                _ = incoming => (),
                _ = outgoing => (),
            }
        });
    }
}

impl TestWebsocket {
    /// Register that you want to talk to a computer. Will not block, so computer might not
    /// immediately be available.
    pub async fn new(id: u16) -> Result<Self, TestWebsocketError> {
        // Make sure websocket is running
        // TODO: Nicer way of globally intializing the websocket server
        run_websocket().await;

        let registry = get_registry();

        // Don't hand out to the registry if items already exist.
        if registry.contains_key(&id) {
            return Err(TestWebsocketError::AlreadyTaken);
        }

        // Create the channels that we communicate over. Don't buffer(?)
        // TODO: What should this limit be in final implementation?
        let (to_test_tx, to_test_rx) = mpsc::channel::<String>(1);
        let (from_test_tx, from_test_rx) = mpsc::channel::<String>(1);

        // Add this to the registry
        registry.insert(
            id,
            ComputerChannel {
                to_test: to_test_tx,
                from_test: from_test_rx,
            },
        );

        // Now give back the other side of the channel to the caller
        Ok(Self {
            id,
            sender: from_test_tx,
            receiver: to_test_rx,
        })
    }
}

// clean up websockets
impl Drop for TestWebsocket {
    fn drop(&mut self) {
        // Remove the socket from the registry if its still in there
        let registry = get_registry();
        // No use for the return value
        let _ = registry.remove(&self.id);
    }
}

/// Basic test of the websockets.
///
/// Very simple, really just seeing if stuff panics.
/// We pick a very high socket number so we do not interfere with other tests.
#[tokio::test]
async fn basic_test_websocket() {
    // Open the socket, then end the test, which will drop and close it.
    let handle = TestWebsocket::new(u16::MAX - 1).await.is_ok();
    assert!(handle)
}

/// We should not be able to open the same websocket twice.
#[tokio::test]
async fn double_open_websocket() {
    let handle = TestWebsocket::new(u16::MAX - 2).await.is_ok();
    let handle2 = TestWebsocket::new(u16::MAX - 2).await.is_err();
    assert!(handle);
    assert!(!handle2);
}
