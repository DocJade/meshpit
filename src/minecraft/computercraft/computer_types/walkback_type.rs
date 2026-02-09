// The walkback format.

use std::collections::{HashMap, HashSet};

use serde::Deserialize;

use crate::minecraft::types::{CoordinatePosition, MinecraftPosition};
use crate::minecraft::vanilla::block_type::{MinecraftBlock, PositionedMinecraftBlock};

/// See `walkback.lua` for more information.
#[derive(Debug, Deserialize)]
pub struct Walkback {
    pub cur_position: MinecraftPosition,
    pub walkback_chain: Option<Vec<CoordinatePosition>>,
    // During the de-serialization process we pull the coordinates back out again,
    // since rust can do struct indexed hashmaps :D
    pub chain_seen_positions: Option<HashMap<CoordinatePosition, u16>>,
    pub all_seen_positions: Option<HashMap<CoordinatePosition, bool>>,
    pub all_seen_blocks: Option<HashMap<CoordinatePosition, PositionedMinecraftBlock>>,
}
