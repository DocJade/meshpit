# Networking
All networking on the turtles is done via the `networking` module. Using bare modem calls is against da rules. Even GPS has to go through this.

# Globals
The networking implementation has a global state to keep track of several important details. These details are explained further in the code block below.
```lua
networking_globals = {
    -- The last time we were able to talk directly to the control computer, expressed as
    -- a `timestamp` using `os.epoch("ingame")`.
    -- This timestamp is updated every time we get an `ack` from the control computer.
    last_online = number,

    -- A boolean to represent if we are currently online or not.
    -- The value here is determined by several factors. See `offline mode`
    currently_online = bool,

    -- There are several operating modes that can be used,
    -- since at different parts of the game, we might not have wireless communication.
    mode = operating_mode,

    -- The UDP packet queue.
    udp_queue = [packet, ...]

    -- To prevent pointless rebroadcasting of packets, on top of packet forming, we can also
    -- re-use the return routes for computers we've talked to.
    -- Routes also keep track of the last time they were used via a `timestamp.`
    saved_routes = Hashmap<id, (timestamp, route)>

}

-- The different operating modes.
-- This is an Enum.
operating_mode = {
    "label",
    "wired",
    "wireless",
    -- "ender",
}

-- The representation of a route.
-- Routes are expressed as a list of computer ID's, not including ourselves.
route = [number, ...]
```

# Message format
Modems messages have a standard event as defined in CC:Tweaked [here](https://tweaked.cc/event/modem_message.html), but we parse that format into our own format on incoming and outgoing messages.

```lua
-- The message format that networking uses internally.
-- We basically have to re-implement standard TCP/IP networking. FUN!
packet = {
    -- The unique ID of this packet. This is used to prevent packet storms.
    -- UUID's are represented as a random 64 bit number.
    -- Remember to re-seed the RNG!
    -- Should be at least 128 bits.
    id = UUID,

    -- What channel this packet is from / for.
    -- See the section below on Turtle group channels.
    channel = number,

    -- The ID of the recipient computer.
    -- This is not set for broadcast packets, such as GPS, or network layout mapping.
    recipient = Option<number>,

    -- The ID of the sending computer.
    sender = number,

    -- The computers allowed to re-transmit this packet.
    -- This is implemented as a hashset (number, true) of computers.
    -- However, if `-1` is `true`, then this packet is allowed to be broadcast by all computers.
    -- This table is really only used when we know an exact route to a destination, thus you should check
    -- for the `-1` case before checking if your ID is in the hashset.
    allowed = hashset<number>,
    
    -- What computers have transmitted this message. This hop list can be used by the recipient computer to
    -- send messages back to us through a known good path, and this will prevent useless re-broadcasts of packets,
    -- preventing lag.
    -- Implemented as an array of computer IDs. The sender is the first ID in the list.
    hop_list = [number]

    -- Where the target computer for this packet is.
    -- This is optional, and if set, will be used to beam-form this
    -- packet towards a position.
    recipient_pos = Option<position>

    -- We also provide where we are, so return packets can be formed towards us.
    -- This is set right before the packet is broadcast, so offline packets don't have
    -- a stale position.
    sender_pos = position

    -- The body / data of the packet.
    -- This can be anything.
    body = anything,

    -- The time this packet was sent, can be used to calculate ping times if we want to do that for some reason.
    -- Should be set to `os.epoch("ingame")` right before sending.
    -- We can also use this to detect networking deadzones, since packets from very long ago indicate that
    -- the packet had to wait for a network connection.
    timestamp = number,

    -- How many more hops this packet has to live.
    -- Packets with 0 TTL will not be rebroadcast.
    ttl = number,
}
```

However, we don't want to have to construct this entire packet ourselves outside of the networking code, so elsewhere we only use a more minimal packet for outgoing data.

```lua
minimal_packet = {
    recipient,
    body
}
```

Received packets only return the body of the packet to the caller, since all of the other surrounding information in a packet is purely for networking.

# Queues
Since we want to send messages while offline, there are methods to queue messages even without an active way to send them, thus there is a FIFO queue messages. The queue is FIFO since once we have a connection, we will be sending them all out as quickly as possible, and messages sent while offline have no guaranteed delivery order.

Attempting to send blocking messages while offline will still work, but they will block forever.

# Methods

## Information
- `networking.online()`
- - Returns a boolean on wether the network is available.
- - This will always return `false` when the turtle is in label mode.
- - This does not guarantee that we are online, it is only a best guess that is meant to be fast.
- - If you need to concretely check if you can reach some destination, use `networking.reachable()` instead.
- `networking.reachable()`
- - Returns a boolean on wether the networking stack was able to reach a target computer.
- - This will always return `false` when the turtle is in label mode.
- - Calling this will also freshen the route between ourselves and the destination. But does incur more delay.
- - You should call `networking.online()` first to prevent pointless reach checks, which are expensive in comparison.

## Sending
- `networking.send_tcp(packet)`
- - Blocks until the packet sends and receives and `ack` from the target computer.
- - This will block ***forever*** until a response is heard. The packet will be re-broadcast occasionally with a new UUID until we hear a response from the destination computer.
- - Theoretically this could never un-block. Use this when you REALLY need to get some data somewhere, and can't continue until you get a response.
- - Returns `nil` if the recipient only ack's without sending any data, or will return the body of the message if the recipient did send data.
- `networking.send_udp(packet)`
- - Will always return `nil`.
- - This function is non-blocking.
- - Packets sent via UDP have absolutely no guarantees around them. Packets sent via UDP may never reach the target destination.
- - However, as a curtesy, UDP packets are queued when offline, and will be only sent when connectivity is restored. However, the sending-order of packets is not guaranteed.

## Receiving
- `networking.wait_control()`
- - This method will block forever until the control computer directly reaches out to this turtle for a reason other than acknowledging a previous packet.
- - Returns whatever data the control computer sent.


# Channel reservations
There are 2^16 channels that can be transmit on. (0 through 65535 inclusive.)
However, modems can only listen to 128 channels at any time. Do note that you can broadcast on channels you do not have open.

We reserve certain channels for explicit uses. Additionally, some channels are required to be listened to, thus a turtle must always have some channels open.

Channels 

| Channel name | Channel number | Justification | Required |
|---|---|---|---|
| Broadcast | 0 | General broadcast channel. | Yes. |
| Fallback transmission | 1 | Used as needed. | Yes. See Turtle Groups. |
| Nearby | 2 | Used to check if anyone can hear us, and communicate with nearby turtles for special functions. | Yes. |
| The Nether | 10 | Used only for transferring packets across the dimension boundary | Forbidden unless you are a dimension repeater. |
| The End | 11 | Used only for transferring packets across the dimension boundary | Forbidden unless you are a dimension repeater. |
| General transmission | 100 through 131 | General traffic. | No*. See Turtle Groups. |
| Emergency | 7700 | Used when turtles are unable to communicate back to the control computer, and require assistance. All packets have a TTL of zero. | Yes.|
| GPS | 15754 | Used for positional data. | Yes. |

# Turtle Groups
At some points, many turtles will need to communicate. Thus we can end up with possibly thousands of turtles listening to a channel. This will cause thousands of events to be queued and processed, which eats up a lot of CPU time. To remedy this, Turtles are split into their own channels based on their computer ID.

The formula for deducing what channel a turtle can be reached at is `id.mod(32) + 100`. This splits traffic up into 32 distinct channels, a number still small enough to let a turtle listen to every communication channel at once if needed.

Do note that splitting turtles into groups like this means that to reach a turtle on channel `101`, there must be turtles, or network repeaters, listening on that channel between you and the destination, which may not always be the case.

Thus while grouped traffic is ***heavily preferred***, it is not possible in all situations. To remedy this, there exists a fallback channel that all turtles must listen and forward traffic on, channel `1`. But using this channel for communication is a ***last resort**.
- However, during early game, there is no reason to split turtles up this heavily, so all traffic will be switched from communicating on exclusively channel `1` to the sub-groups once the control computer deems necessary via a OTA update.

# A note on timeouts
Packets do not time out. Ever.
This may seem like a bad idea, but the complexities of packets being dropped and re-sending dropped data is very complicated. We are okay with making a turtle wait forever for a response.

While waiting for a response for a particular packet, we are in full control of the turtle. Thus the turtle can be un-blocked by the OS if needed.

# Operation modes

## Label
In the beginning, there was nothing. Then two turtles looked at each-other and started to chat.

Before we have access to wireless, or even wired communication, we can still directly pass messages from turtle-to-turtle via redstone signaling and changing the label of the computer.

However, the computer label can only be at most 32 characters long, so any communication across this format is very slow, and is really only suited for small amounts of data.

Label mode is the only allowed networking state when a turtle doesn't have a wireless modem attached to itself. Label mode will automatically be switched off when a turtle has a wireless modem, or when a turtle is standing next to a wired modem that it is able to use.

### Label communication protocol

When a computer is in Label mode, it will watch for an peripheral attach event.
If one is seen, the computer will immediately set their redstone output to high on the side that the event came from, then check for a high signal from the other turtle after 1 second.

If the other turtle does not output redstone on their side, we cancel the handshake, since they are not interested.

After confirming the other turtle will be participating, both computers will wrap each-other as peripherals, and lower their redstone signals.

Once the peripherals have been wrapped, the turtles will set their label to their computer ID.

The turtles will compare their computer ID to the other turtles ID, whoever has the lower ID is hereafter referred to the `main` turtle.

Once the main turtle has been deduced, the main turtle will raise its redstone line again and wait for the other turtle to raise theirs.

Once the other turtle raises their signal, the packet dance can begin.

Packets are transmit via turning them into JSON before sending them. Do be careful to include `nil` in the json!

The packet dance has the following steps:
- The sender turtle sets their label to `START` and waits for the recipient to set theirs to `WAITING`.
- When the recipient is `WAITING`, the sender will send the next 32 characters of packet data, and wait for the recipient to set their label to that same data.
- Once the recipient sets their label in response, the next 32 characters are sent, with the same rules as the previous step.
- This repeats until the sender runs out of data, at which time they will set their label to `DONE` and waits for the recipient to respond with `SWITCH`.
- The sender responds with `WAITING`, and the process repeats, in the other direction.
- When it is a turtle's turn but it has nothing left to send, it will respond with `FINISH` instead of `SWITCH`.
- When a turtle sees `FINISH` it will respond with `GOODBYE`.
- The turtle broadcasting `FINISH` waits for `GOODBYE`, then will un-wrap the peripheral of the other turtle, and say `SEE YA!`. The turtle then waits 5 seconds before it clears its label, and is officially disconnected.
- The turtle broadcasting `GOODBYE` waits for `SEE YA!`, then un-wraps the other turtle, clears their label, and is officially disconnected.

### Limitations in Label mode
General packet data can still be exchanged between turtles in the hopes of communicating with other turtles (or the control computer) further away, but turtles cannot diverge from the tasks they are given, so sending a packet to anybody besides the turtle next to you has no guarantee to ever make it to your recipient. If you block on a packet sent over label, you would need a miracle to get the packet there, and back again within 10 minutes.

Thus no blocking operations are allowed while in label mode, and you are not allowed to send packets to anyone besides the turtle/computer next to you.

Turtles can only talk to 1 adjacent turtle while in Label mode. If another turtle shows up to the party, it's handshake will be ignored, since the currently communicating pair of turtles are busy.

## Wired
There isn't anything special about wired, besides requiring the turtle to be next to a modem block. The mode of the turtle will be automatically switched from Label to Wired and back automatically. However, you cannot switch from Wireless to Wired mode.

### Wired communication protocol
Wired communication will work in the exact same way as Wireless communication, with the following features disabled:
- Hop limits above 0 (TTL 0)
- - If the packet cannot be received by the recipient without hopping, that means the recipient is not on this wired network.
- Hop lists
- - There is no reason to track hops, or restrict them.
- Beam forming, anything position related.
- - There is no reason to beam-form when directly connected.
- Using Turtle group channels
- - Wired networking is used for early game. There is no need to split up traffic.

## Wireless
Packets sent in wireless mode will time out in 10 seconds.

### Wireless communication protocol

A `valid` value here refers to any data that is relevant to the packet being sent, while also being fresh enough to be considered for use.

### Outgoing - TCP
- Fill in remaining data on the packet we are about to send.
- - Generate the UUID for `id`
- - - A new UUID will be generated every time we attempt to re-broadcast.
- - Pick the `channel` to send on
- - Set up the `allowed` list if we have a valid path to the destination computer set
- - Put self in the first element of `hop_list`
- - Fill in the `recipient_pos` if we happen to know it, and is valid. For example, we know that the control computer is always at `0,(unimportant),0`.
- - Set the `sender_pos`
- - Fill in the `timestamp`
- - - This timestamp is NEVER updated past this point. This timestamp is meant to mark the original time we tried to broadcast this message.
- - Set the TTL to a reasonable amount.
- - - If we have a path to the destination, it should be 1 more than the length of the `allowed` list.
- - - Otherwise a best guess can be made by using the length of the hop list of the most recently received packet.
- - - If no response is heard, we will use the `nearby` channel to see if anyone can hear us. If not, we will go offline.
- - - If there is someone to listen, the TTL will be increased on each subsequent re-broadcast up to 32. At which point, if we still don't get any response, we assume we are offline.
- - - Note that this all implies we are speaking to the control computer. Since turtle-to-turtle communication is rare and usually only takes place on the `emergency` or `local` channels, which have zero TTL anyways. If at some point turtles are allowed to talk to each-other for some reason, this logic will be changed.
- Once the packet is constructed, send it out immediately and wait for a response.
- - If there is no response within the default timeout period, re-transmit it with a new UUID and higher TTL as specified above until we either get a response, or we switch to offline mode.
- Once a response is received, we do a few more things before returning to the caller:
- - Add the 
- Finally, we return the value received from the destination. Either `nil` for the default `"ack"` response, or the custom body data that was sent in the response.

### Outgoing - UDP
- Fill in remaining data on the packet we are about to send.
- - See TCP.
- Put the packet in the UDP buffer.

### UDP Buffer
If the turtle is not offline (see `offline mode`), every time the turtle yields to the networking stack, we will send one packet from the queue before moving onto the rest of the networking logic.

This allows a lot of messages to be queued quickly, then later sent without flooding the network all at once.

We do our best to detect if we are online, but UDP packets are not guaranteed to be delivered, so incorrectly transmitting packets while there is nobody around is fine. We would prefer to lose these packets than to waste time querying for neighbors.

### Incoming
When blocking for an incoming packet, the logic is very simple. Just wait for a packet from the control computer that is not `"ack"`.

This type of incoming blocking should only be used by the OS/Task scheduler when we are out of things to do.

## Ender
~~Packets sent in wireless mode will time out in 1 second, due to them never needing to hop to their destination, but still needing to account for the possibility of the recipient being busy.~~

~~It is highly unlikely turtles will ever fully transition to ender modems, thus ender modem interactions are treated the same as wireless mode. But ender modems are not allowed to respond to the following packet types:
~~- Any broadcast packet~~

~~Ender modems can hear, and be heard, from anywhere (Technically at most 2^32-1, but going that far with turtles would take many years.). In practical terms, this means that the moment we have an ender modem for the control computer, almost all of our networking needs disappear. The only remaining networking needs would be GPS, which then could also be handled with 2 more ender modems.~~

~~However, due to the ability to be heard anywhere, sending packets that can be heard by everyone will instantly create mass amounts of lag. So despite the possible advantages of ender modems in applications like GPS and Broadcast packets, they should NOT be used for any packets that aren't directed at a specific Turtle Group.~~

Ender modems are only used to transmit information between dimensions on the dedicated cross-dimension channels. See `Cross-dimension networking`.

Ender modems should not be used in any other circumstance due to the vast amount of events they would create and consume.

## Offline mode
When in offline mode, all network calls still work. UDP packets can continue to be queued normally, and TCP packets will still block as they would normally, albiet for probably a lot longer than usual.

If no network traffic has happened in a while, or we haven't talked to the control computer directly in a while, we will reach out to the control computer to check if we are online. If we are unable to contact the control computer, we will enter offline mod.

When in offline mode, we will periodically attempt to find turtles near us by reaching out on the `nearby` channel.
- Do note that the turtle is still allowed to do other things while offline, unless we are blocking for a TCP packet.

Once there is someone nearby, we will immediately tell that turtle to stop in place. We will then tell that turtle to check if it is online via reaching out to the control computer.
- If that turtle is online, move to the next step.
- If the turtle is also offline, that turtle will not be allowed to move until it becomes online.
- - This behavior of offline mode turtles will slowly build a chain of offline turtles in a hope that the end of the chain will eventually see a network, since chances are that turtles will approach an offline turtle while traveling _away_ from a place within networking range. Thus the chain will continue to grow until the first turtle that started the chain is able to become online.

Once that turtle is confirmed to be online, we will send all of our packets out, mark ourselves as online, and stall for an additional 10 seconds, just in case the control computer decides to give us new tasks. Then finally, we release the lock on the turtle we stopped.
- This will cascade, resulting in all turtles in the chain sending out their buffers before unlocking.

Do note that this does NOT resolve the underlying issue of a lack of connection within an area. And it is very likely that the chain will quickly reform again. As turtles, it is not our job to fix these holes in the network. We depend on the control computer to acknowledge the hole in the network and take steps to remedy it, such as recalling turtles within the affected area, or dispatching new turtles to the area to improve network coverage.

Sending turtles into areas without a connection is a last-resort for the control computer. And as such, tasks relegated to turtles that must explore into un-charted areas should take care to not make TCP network calls from areas with no connection.

# Saved routes
Routes are added to `saved_routes` whenever we receive a packet, overwriting any previous content if we already had a route for that computer.

Routes are removed from the list if we try to use them, and they fail. Additionally, routes are occasionally checked to see if they are still valid if enough time has passed. These checks are:
- Reach out to `nearby`, and check if any of the computers in this route are within range.
- - If there are computers in range, and at least one exists in the route, trim the route (if applicable) to the computer furthest down in the chain, and update the timestamp with the current time.
- - If there are computers in range, but none exist in the route, discard the route entirely.
- - If no computers are nearby, set ourselves to offline mode, and do not remove the route.

Do note that route refreshing only happens when we are online. While offline, if a route is over 10 minutes minutes old, it is discarded.

If the route is <=3 hops, discard it.

Holding onto a route for a long time might not be in our best interests, as its possible that network topology has changed, and/or we are not using an optimal route. To solve this, there is a 1/(route hop count * 2) chance every that when a route is refreshed, it is discarded.

While in theory we could also deduce if we know a route to a computer based on the fact that is contained within other routes, scanning for computers within each route is slow, and keeping an up-to-date hashset is tedious, therefore this behavior will not be implemented. Especially since almost all communication will happen between the control computer and a specific turtle, not turtle-to-turtle.

# Cross-dimension networking
When first exploring new dimensions, such as the nether, it is unlikely that ender modems will be available for use yet. Thus turtles in other dimensions must be set to `Offline` when crossing into a new dimension. Extra care must be taken on assigning tasks to turtles in dimensions without networking infrastructure, as going `Offline` in another dimension would be a death sentence, resulting in a never-ending chain of turtles trying to obtain network access. Thus, turtles entering a dimension without networking infrastructure should have their wireless modems removed, relegating them to only using Label networking. This prevents turtle chaining, and is generally safe to use.

Once ender modems are available, networking infrastructure can be built out in the new dimension by sending a turtle to the the dimension to act as repeater.

Turtles acting as an dimensional repeater repeater between dimensions are required to have a regular modem in addition to their end modem.

The ender modems can only be used to pull packets across the dimension boundary, not to re-transmit the packet once it has hit the new dimension. This is for the same reasons that ender modems are banned for general networking use. All packets received from a ender modem must be re-transmit using the standard modem.

Thus, once a turtle acting as a repeater has been set up, more turtles can be introduced to start creating the 