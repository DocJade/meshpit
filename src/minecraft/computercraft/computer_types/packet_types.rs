// The packet format received and sent to the turtle

use std::str::FromStr;

use regex::Regex;
use serde::{de::Error, Deserialize, Serialize};
use serde_json::Value;

use crate::{minecraft::computercraft::computer_types::{cc_panic::LuaPanic, walkback_type::Walkback}};
use crate::minecraft::types::CoordinatePosition;

const INCORRECT_PACKET_TYPE_ERROR: &str = "wrong packet type";

/// Types of packet
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PacketType {
    Panic,
    Walkback,
    Unknown,
    Debugging,
}

// ==================
// Raw packet
// ==================

/// Packets sent to and from turtles.
/// 
/// The Internal type of this packet is not immediately known, so you must
/// cast this into one of the other known packet types before manipulating it
/// further.
#[derive(Debug, Deserialize)]
pub struct RawTurtlePacket {
    /// The turtle that sent this packet. We rename it to `from` on the rust
    /// side instead of `id` to be more clear that this is from a turtle with
    /// this id, not the ID of the message.
    #[serde(rename = "id")]
    from: u16,
    /// The UUID of the packet
    uuid: String,
    /// What kind of packet this is 
    packet_type: PacketType,
    /// The inner, un-converted data.
    inner_data: String
}

impl RawTurtlePacket {
    /// Get the kind of this packet. You may then use this to decide how to
    /// cast this packet.
    pub fn packet_type(&self) -> &PacketType {
        &self.packet_type
    }
}

// ==================
// Sub packet types
// ==================

// =========
// Panic
// =========

/// Turtles return this packet type when they fail catastrophically.
/// This packet type is mostly intended for troubleshooting and post-runtime
/// inspection. Additionally, turtles that return this packet will reboot
/// themselves, and may need to be re-initialized.
pub struct PanicPacket {
    /// The turtle that sent this packet
    pub from: u16,
    /// The UUID of the packet
    pub uuid: String,
    /// The panic data
    pub panic_data: LuaPanic
}

impl TryFrom<RawTurtlePacket> for PanicPacket {
    // This should be able to grab all of the panic data always,
    // but we still can error if needed.
    type Error = serde_json::error::Error; 

    fn try_from(value: RawTurtlePacket) -> Result<Self, Self::Error> {
        if value.packet_type == PacketType::Panic {
            return Err(serde_json::error::Error::custom(INCORRECT_PACKET_TYPE_ERROR))
        }

        let panic_data: LuaPanic = serde_json::from_str(&value.inner_data)?;

        Ok(PanicPacket {
            from: value.from,
            uuid: value.uuid,
            panic_data,
        })
    }
}

// =========
// Walkback
// =========

/// Walkback dumps returned from turtles. May be very large, so avoid cloning
/// and pass by reference only.
pub struct WalkbackPacket {
    /// The turtle that sent this packet
    pub from: u16,
    /// The UUID of the packet
    pub uuid: String,
    /// The walkback data contained within this packet
    pub walkback: Walkback
}

impl TryFrom<RawTurtlePacket> for WalkbackPacket {
    type Error = serde_json::error::Error; // We either cast, or don't.

    fn try_from(value: RawTurtlePacket) -> Result<Self, Self::Error> {
        if value.packet_type == PacketType::Walkback {
            return Err(serde_json::error::Error::custom(INCORRECT_PACKET_TYPE_ERROR))
        }

        // Attempt to cast down into the walkback type.
        let convert: Walkback = serde_json::from_str(&value.inner_data)?;

        // Temporary.
        Ok(WalkbackPacket {
            from: value.from,
            uuid: value.uuid,
            walkback: convert,
        })
    }
}

// =========
// Unknown
// =========

/// It is the Lua side's responsibility to always properly tag packets.
/// This is the packet you get when that promise fails to be met. The data in
/// this packet may be completely nonsensical, even the from id could be wrong.
/// 
/// No guarantees about the validity of the data are made.
pub struct UnknownPacket {
    /// The turtle that sent this packet
    pub from: u16,
    /// The UUID of the packet
    pub uuid: String,
    /// The data contained within the packet as a string.
    pub unknown_data: String
}

impl TryFrom<RawTurtlePacket> for UnknownPacket {
    type Error = serde_json::error::Error; // We either cast, or don't.

    fn try_from(value: RawTurtlePacket) -> Result<Self, Self::Error> {
        if value.packet_type == PacketType::Walkback {
            return Err(serde_json::error::Error::custom(INCORRECT_PACKET_TYPE_ERROR))
        }

        // Temporary.
        Ok(UnknownPacket {
            from: value.from,
            uuid: value.uuid,
            unknown_data: value.inner_data,
        })
    }
}

// =========
// Debugging
// =========

/// These packets are sent out of the turtle via the `debugSend` call on network.
/// 
/// These packets always contain a single string, and that's it.
pub struct DebuggingPacket {
    /// The turtle that sent this packet
    pub from: u16,
    /// The UUID of the packet
    pub uuid: String,
    /// The data contained within the packet as a string.
    pub debug_message: String
}

impl TryFrom<RawTurtlePacket> for DebuggingPacket {
    type Error = serde_json::error::Error; // We either cast, or don't.

    fn try_from(value: RawTurtlePacket) -> Result<Self, Self::Error> {
        if value.packet_type == PacketType::Walkback {
            return Err(serde_json::error::Error::custom(INCORRECT_PACKET_TYPE_ERROR))
        }

        // Temporary.
        Ok(DebuggingPacket {
            from: value.from,
            uuid: value.uuid,
            debug_message: value.inner_data,
        })
    }
}


/// Attempt to pull a coordinate position from a string. Errors with unit type if
/// this is not a coordinate.
impl FromStr for CoordinatePosition {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        // Capture groups for xyz, anchored on start and end so must match all 3
        let regex = Regex::new(r"^x:(-?\d+)\|y:(-?\d+)\|z:(-?\d+)$").expect("This is valid regex.");

        // Captured?
        // If not, return early
        let captures = regex.captures(s).ok_or("no capture")?;

        // Got it, captures
        Ok(Self {
            x: captures[1].parse().map_err(|_| "invalid x integer")?,
            y: captures[2].parse().map_err(|_| "invalid y integer")?,
            z: captures[3].parse().map_err(|_| "invalid z integer")?
        })
    }
}

// #[serde(try_from = "String")]
impl TryFrom<String> for CoordinatePosition {
    type Error = String;
    fn try_from(s: String) -> Result<Self, Self::Error> {
        s.parse()
    }
}