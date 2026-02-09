use std::collections::HashMap;

use serde::Deserialize;
use serde_json::Value;

use crate::minecraft::computercraft::computer_types::lua_types::{LuaPackedTable, LuaValue};

/// When computers panic they return a special type.
///
/// These contain a lot of funky data, and thus are basically un-derivable.
///
/// See panicking.md
#[derive(Debug, Deserialize)]
pub struct LuaPanic {
    stack_trace: String,
    locals: LuaPackedTable,
    up_values: LuaPackedTable,
    #[serde(flatten)] // Grab all of the fields that are unmatched.
    unknown_extra_data: HashMap<String, LuaValue>,
}
