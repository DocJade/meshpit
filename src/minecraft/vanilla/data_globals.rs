// We only want to load in the data that we need once, as to not constantly re-load stuff. Thus we have a global.

use std::sync::Arc;

use log::info;
use mcdata_rs::IndexedData;
use once_cell::sync::Lazy;

pub static CURRENT_MINECRAFT_VERSION: &str = "1.21.1";

static MINECRAFT_DATA: Lazy<Arc<IndexedData>> = Lazy::new(|| {
    // on first run this downloads the data, which can take a long, long time.
    info!(
        "Setting up Minecraft data. If this is the first time we've set this up, this may take a while to download."
    );

    // We assume that we can load in the minecraft data, if we can't get it, we're doomed.
    mcdata_rs::mc_data(CURRENT_MINECRAFT_VERSION)
        .expect("Unable to load Minecraft data! Is the version wrong?")
});

// Since we're in a double reference situation, we annoyingly have to do this cast nonsense.
pub fn get_mc_data() -> &'static IndexedData {
    #[allow(clippy::explicit_auto_deref)] // want to show the deref happening
    &**MINECRAFT_DATA
}
