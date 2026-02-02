// Yes, we even test the lua.
// SInce we have our own json serializer and de-serializer, its important to test these.

use mlua::prelude::*;

use crate::minecraft::computercraft::lua_types::table::PairedLuaTable;


const HELPERS: &str = include_str!("helpers.lua");

#[tokio::test]
// Attempt to serialize a variety of tables.
async fn lua_serialization() {
    let lua = Lua::new();
    // Load in the helper functions
    let helpers: LuaTable = lua.load(HELPERS).eval().unwrap();

    // Grab the json serializer
    let json_fn: LuaFunction = helpers.get("prepareForJson").unwrap();

    // Try to serialize an array style table out.
    let array_table = lua.create_table().unwrap();
    array_table.push("one").unwrap();
    array_table.push("two").unwrap();
    array_table.push("three").unwrap();
    let array_table_out: LuaTable = json_fn.call(array_table).unwrap();

    let array_converted: PairedLuaTable;

    todo!()


}