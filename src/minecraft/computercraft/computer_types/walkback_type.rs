// The walkback format.

use std::collections::{HashMap, HashSet};

use serde::Deserialize;

use crate::minecraft::types::{MinecraftPosition, CoordinatePosition};
use crate::minecraft::vanilla::block_type::MinecraftBlock;

/// See `walkback.lua` for more information.
#[derive(Debug, Deserialize)]
pub struct Walkback {
    pub cur_position: MinecraftPosition,
    pub walkback_chain: Vec<CoordinatePosition>,
    // During the de-serialization process we pull the coordinates back out again,
    // since rust can do struct indexed hashmaps :D
    pub chain_seen_positions: HashMap<CoordinatePosition, u16>,
    pub all_seen_positions: HashSet<CoordinatePosition>,
    pub all_seen_blocks: HashMap<CoordinatePosition, MinecraftBlock>
}