// Lua tables are really funky, and the json exporting methods built into CC:Tweaked aren't quite
// enough. So we have our own custom format.

use serde::{Deserialize, Serialize};

// To pull everything back out we need to first pre-cast from `value` to a
// packed table (if it is one) or a primitive.

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(untagged)] // Try to deserialize in the order that the enums are laid out.
pub enum LuaValue {
    // Packed table format
    Table(LuaPackedTable),

    // Primitives
    String(String),
    Integer(i64),
    Float(f64),
    Bool(bool),

    // Empty
    Null,
}

/// All of the tables we export from minecraft will be in this `key, value`
/// pair format. Thus tables just turn into an array of pairs.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LuaPackedTable {
    pub pairs: Vec<LuaKeyValuePair>,
}

// For the key-value pairs seen in our table export format
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct LuaKeyValuePair {
    // These can be recursive via containing more tables, be careful.
    pub key: LuaValue,
    pub value: LuaValue,
}
