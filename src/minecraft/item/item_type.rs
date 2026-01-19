// The basic Minecraft item type.
// This is our base type for every kind of item in Minecraft, this can also be cast to MinecraftBlock (TODO: if i ever do that or need it)

use std::fmt::Display;

#[derive(Clone, Copy)]
pub enum MinecraftItem {
    LimeConcrete,
    RedConcrete,
    YellowConcrete,
    Netherrack,
    GoldBlock,
    RedstoneTorch,
    Fire,
    CCComputerNormal,
    CCTurtleNormal,
}

impl Display for MinecraftItem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MinecraftItem::LimeConcrete => write!(f, "minecraft:lime_concrete"),
            MinecraftItem::RedConcrete => write!(f, "minecraft:red_concrete"),
            MinecraftItem::YellowConcrete => write!(f, "minecraft:yellow_concrete"),
            MinecraftItem::CCComputerNormal => write!(f, "computercraft:computer_normal"),
            MinecraftItem::CCTurtleNormal => write!(f, "computercraft:turtle_normal"),
            MinecraftItem::Netherrack => write!(f, "minecraft:netherrack"),
            MinecraftItem::GoldBlock => write!(f, "minecraft:gold_block"),
            MinecraftItem::RedstoneTorch => write!(f, "minecraft:redstone_torch"),
            MinecraftItem::Fire => write!(f, "minecraft:fire"),
        }
    }
}