// Lua tables are really funky, and the json exporting methods built into CC:Tweaked aren't quite
// enough. So we have our own custom format.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// All of the tables we export from minecraft will be in this `key, value` pair format. Thus
/// tables just turn into an array of pairs.
#[derive(Debug, Serialize, Deserialize)]
pub struct PairedLuaTable {
    pairs: Vec<LuaKeyValuePair>
}

// For the key-value pairs seen in our table export format
#[derive(Debug, Serialize, Deserialize)]
pub struct LuaKeyValuePair {
    key: Value,
    value: Value,
}