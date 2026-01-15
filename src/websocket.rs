// management of the websocket

use tokio::{net::{TcpListener, TcpStream}, sync::mpsc};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{SinkExt, StreamExt};


pub struct CCWebsocket {
    // Messages put into this channel are sent into Minecraft.
    // TODO: dedicated message send type instead of strings
    outgoing_tx: mpsc::UnboundedSender<String>,
}

impl CCWebsocket {
    /// Make a new websocket connection.
    /// Returns a `(CCWebsocket, 
    pub async fn new(stream: TcpStream) -> (Self, mpsc::UnboundedReceiver<String>) {
        // TODO: error handling
        let websocket_stream = accept_async(stream).await.expect("Failed to accept websocket!");
        
        // Split the websocket into its sender and receiver components
        let (mut websocket_sender, mut websocket_receiver) = websocket_stream.split();

        // TODO: Non-string types
        // Outgoing channel
        let (outgoing_tx, mut outgoing_rx) = mpsc::unbounded_channel::<String>();
        // Incoming channel
        let (incoming_tx, incoming_rx) = mpsc::unbounded_channel::<String>();

        // set up threads to send the contents of the channels out the websocket, and vice-versa

        // Outgoing
        tokio::spawn(async move {
            while let Some(outgoing) = outgoing_rx.recv().await {
                // TODO: detect failures in sending
                websocket_sender.send(Message::Text(outgoing.into())).await.unwrap();
            }
        });

        // Incoming
        tokio::spawn(async move {
            while let Some(incoming) = websocket_receiver.next().await {
                // TODO: Error handling
                let text = incoming.unwrap().into_text().unwrap();
                incoming_tx.send(text.to_string()).unwrap()
                
            }
        });

        (Self { outgoing_tx }, incoming_rx)
    }
    /// Send a message out the websocket
    pub fn send(&self, string: String) -> Result<(), ()> {
        // TODO: non-string type
        // TODO: error handling
        self.outgoing_tx.send(string).unwrap();
        Ok(())
    }
}