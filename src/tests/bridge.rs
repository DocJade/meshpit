// Bridge between Minecraft and this repo. Since for testing we need to start a server.

use std::{
    cell::OnceCell,
    fs::{self, OpenOptions},
    io::Write,
    num::NonZero,
    path::{Path, PathBuf},
    process::Stdio,
    sync::{Arc, OnceLock},
};

use rcon::{AsyncStdStream, Connection};

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::time::{Duration, timeout};

use log::{debug, error, info, warn};
use once_cell::sync::Lazy;

// Urls for the installers and such.
static CURRENT_MINECRAFT_VERSION: &str = "1.21.1";
static MINECRAFT_RCON_PORT: &str = "25575";
// nobody will ever guess 1235
static MINECRAFT_RCON_PASSWORD: &str = "1235";
static JVM_ARGS: &str = "-XX:+UseZGC -XX:+ZGenerational";
static NEOFORGE_INSTALLER_URL: &str = "https://maven.neoforged.net/releases/net/neoforged/neoforge/21.1.218/neoforge-21.1.218-installer.jar";
static MOD_URLS: &[&str] = &[
    "https://cdn.modrinth.com/data/gu7yAYhd/versions/hAW75xeY/cc-tweaked-1.21.1-forge-1.117.0.jar",
    "https://cdn.modrinth.com/data/uXXizFIs/versions/CnpoQxCx/ferritecore-7.0.2-neoforge.jar",
    "https://cdn.modrinth.com/data/gvQqBUqZ/versions/G5SDYehn/lithium-neoforge-0.15.1%2Bmc1.21.1.jar",
    "https://cdn.modrinth.com/data/nmDcB62a/versions/8Be8uJW6/modernfix-neoforge-5.25.1%2Bmc1.21.1.jar",
    "https://cdn.modrinth.com/data/l6YH9Als/versions/v5qtqRQi/spark-1.10.124-neoforge.jar",
];
// TODO: Use `spark` for profiling tests for performance testing?

// we are assuming you run `cargo test` while in `/meshpit`
static SERVER_DIRECTORY: &str = "./test_server";

/// Information to keep track of where mc tests are done.
// #[derive(Debug)]
pub struct MinecraftEnvironment {
    process: Option<tokio::process::Child>, // into sandwich
    rcon_connection: Option<rcon::Connection<AsyncStdStream>>,
    server_dir: PathBuf,
}

// When we are running tests, this will run afterwards to make sure we shut down the server.
#[cfg(test)]
#[ctor::dtor] // When all of the tests are over, we need to clean up (ie shut down) the minecraft server.
fn post_test_shutdown() {
    info!("Running post-test cleanup...");

    // TODO: Add a flag to keep the server running and to delay tests starting initially to allow player to join.
    // std::thread::sleep(Duration::from_secs(300));

    // function is async so we need another thread.
    let handle = std::thread::spawn(|| {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("Should be able to spawn a runtime for lazy making.");

        #[allow(clippy::await_holding_lock)] //TODO: idk what it wants, fix later
        rt.block_on(async {
            let mut guard = crate::tests::test_harness::MINECRAFT_TESTING_ENV
                .lock()
                .expect("We should have the only reference");
            let server: &mut MinecraftEnvironment = &mut guard.environment;
            server.shutdown_and_wait().await;
        })
    });
    info!("Done cleaning up. Goodbye.");
}

impl MinecraftEnvironment {
    /// Start the Minecraft server
    pub(super) async fn start() -> Self {
        // Don't let us start the server multiple times.
        static NO_REPEATS: OnceLock<bool> = OnceLock::new();
        if NO_REPEATS.set(true).is_err() {
            panic!("Tried to start the test server twice!")
        };

        info!("Starting test server... ({CURRENT_MINECRAFT_VERSION})");
        // Check if the server directory already exists
        let server_dir = Path::new(SERVER_DIRECTORY).to_path_buf();
        info!("Checking for server in {}...", server_dir.to_string_lossy());
        if server_dir.exists() && server_dir.is_dir() {
            // Should already be set up.
            info!("Server directory exists, assuming its already set up...");
        } else {
            // run setup first.
            info!("Server not present, doing initial server setup...");
            MinecraftEnvironment::setup(server_dir.clone()).await;
            info!("Done with first time server setup.");
        }

        let mut server = MinecraftEnvironment {
            process: None,
            rcon_connection: None,
            server_dir: server_dir.clone(),
        };

        // clean up old saves
        info!("Cleaning up old worlds...");
        server.cleanup();

        // Launch that mf
        info!("Starting server...");
        server.start_and_wait().await;
        info!("Server ready!");

        // make sure we actually got a server
        assert!(
            server.process.is_some(),
            "We need a child process at this point."
        );

        // attach rcon
        server.attach_rcon().await;

        server
    }
    /// Check if server is still running
    pub fn is_running(&self) -> bool {
        self.process.is_some()
    }
    /// Get the server folder
    pub fn get_server_folder(&self) -> PathBuf {
        self.server_dir.clone()
    }
    /// Set up the server environment via downloading, installing, and configuring.
    async fn setup(server_dir: PathBuf) {
        // make the dir
        if let Err(error) = std::fs::create_dir(&server_dir) {
            error!("Unable to setup server directory! Do we have permission?");
            error!("Error: {error:#?}");
            panic!();
        };

        // make sure we have java
        if let Err(error) = Command::new("java").arg("-version").status().await {
            error!("Failed to check Java version! Is Java installed?");
            error!("{error:#?}");
            panic!()
        };

        // download neoforge
        info!("Downloading NeoForge... This might take a second (if you have bad internet)");
        let jar_path = server_dir.join("installer.jar");
        let neoforge = reqwest::get(NEOFORGE_INSTALLER_URL)
            .await
            .expect("Should be able to get it")
            .bytes()
            .await
            .expect("Should be able to cast to bytes.");

        fs::write(&jar_path, &neoforge).expect("Should be able to write");

        // Now run the neoforge installer.
        let status = Command::new("java")
            .arg("-jar")
            .arg("installer.jar")
            .arg("--installServer")
            .current_dir(&server_dir)
            .stdout(std::process::Stdio::inherit()) // we print everything to the console just so
            .stderr(std::process::Stdio::inherit()) // if it fails, its easier to see. lol.
            .status()
            .await
            .expect("Should run");

        if !status.success() {
            error!("Failed to install NeoForge!");
            error!("{status}");
            panic!()
        }

        // Now delete the installer file
        if let Err(error) = fs::remove_file(&jar_path) {
            // not the end of the world. Just an extra file.
            warn!("Failed to delete the installer jar, but thats fine.");
            warn!("Error: {error:#?}");
        };

        info!("Finished installing NeoForge!");

        // Time to stuff some mods in there
        info!("Downloading required mods...");
        let mod_folder: PathBuf = server_dir.join("mods");

        // make the mod folder in-case it doesnt exist yet.
        let _ = std::fs::create_dir(&mod_folder); // if this fails we'll die anyways.

        for url in MOD_URLS {
            let mod_filename = url
                .split('/')
                .next_back()
                .expect("There should be a file name at the end.");
            info!("Downloading `{mod_filename}`...");
            let download = reqwest::get(*url)
                .await
                .expect("Should be able to get it")
                .bytes()
                .await
                .expect("Should be able to cast to bytes.");
            fs::write(mod_folder.join(mod_filename), download).expect("Should be able to write");
        }

        info!("Finished downloading mods!");

        info!("Accepting EULA...");
        let eula_path = server_dir.join("eula.txt");
        fs::write(eula_path, "eula=true").expect("should be able to make the eula file");

        // now, since we need to edit the computercraft toml, we actually have to start the server for a split second.
        info!("Starting server to get things ready... (This may take a while)");

        let mut server = MinecraftEnvironment {
            process: None,
            rcon_connection: None,
            server_dir: server_dir.clone(),
        };

        server.start_and_wait().await;

        // now shut it down again.
        info!("Shutting it down... (This also may take a while)");
        server.shutdown_and_wait().await;

        // now the toml files should be where we want them, go edit them
        info!("Configuring computercraft...");

        let config_dir = server_dir.join("config");
        let computercraft_toml = config_dir.join("computercraft-server.toml");

        // we expect this to exist
        assert!(
            computercraft_toml.exists(),
            "The toml should be generated when the server starts."
        );

        // edit that mf
        let read = fs::read_to_string(&computercraft_toml).expect("Should be able to read");
        let mut config = read
            .parse::<toml_edit::DocumentMut>()
            .expect("Should be valid toml");

        // Turn up the computer thread count
        // This will be set to half of the host computer's thread count.
        // If we cant read it, just leave it at 1.
        let core_count: i64 = std::thread::available_parallelism()
            .unwrap_or(NonZero::new(1).expect("One is not zero"))
            .get()
            .try_into()
            .expect("if you have more threads than an i64, god help you.");

        config["execution"]["computer_threads"] = toml_edit::value(core_count);

        // let computercraft touch local networks
        // this assumes the private setting is the first one, which it is as of 17/1/2026
        config["http"]["rules"][0]["action"] = toml_edit::value("allow");

        fs::write(&computercraft_toml, config.to_string())
            .expect("Should be able to write back the edited toml.");

        // Now set up the JVM args.
        // We don't wanna force people to use Java 25 or anything, so we will use generic flags.
        // TODO: Add to the documentation that when running a server standalone with this, you should really use the following flags on java 25:
        // -XX:+UseZGC -XX:+UseCompactObjectHeaders <- java 25

        info!("Setting java args...");
        let java_args_file = server_dir.join("user_jvm_args.txt");
        let mut args_editor = OpenOptions::new()
            .append(true)
            .create(false)
            .open(java_args_file)
            .expect("The args file should be there.");
        let formatted_string = format!("\n{JVM_ARGS}");
        args_editor
            .write_all(formatted_string.as_bytes())
            .expect("Should be able to update file.");
        info!("Done!");

        // Enable rcon
        info!("Setting up server.properties...");
        let server_properties_file = server_dir.join("server.properties");
        let mut properties_text =
            fs::read_to_string(&server_properties_file).expect("Should exist.");

        // Since its plaintext, editing this is a bit more annoying.
        // Enable RCON
        properties_text = properties_text.replace("enable-rcon=false", "enable-rcon=true");
        properties_text = properties_text.replace(
            "rcon.port=25575",
            &format!("rcon.port={MINECRAFT_RCON_PORT}"),
        );
        properties_text = properties_text.replace(
            "rcon.password=",
            &format!("rcon.password={MINECRAFT_RCON_PASSWORD}"),
        );

        // motd bc why not
        properties_text = properties_text.replace("motd=A Minecraft Server", "motd=Meshpit Test");

        // spectator gamemode
        properties_text = properties_text.replace("gamemode=survival", "gamemode=spectator");

        // Superflat world
        properties_text = properties_text.replace(
            "level-type=minecraft\\:normal",
            "level-type=minecraft\\:flat",
        );

        // No spawn protection
        properties_text = properties_text.replace("spawn-protection=16", "spawn-protection=0");

        // no villages
        properties_text = properties_text.replace("generate-structures=true", "generate-structures=false");

        // no mobs
        properties_text = properties_text.replace("spawn-animals=true", "spawn-animals=false"); 
        properties_text = properties_text.replace("spawn-monsters=true", "spawn-monsters=false"); 
        properties_text = properties_text.replace("spawn-npcs=true", "spawn-npcs=false"); 

        // replace the old config
        fs::write(server_properties_file, properties_text).expect("Should be able to replace it.");

        info!("Done!");

        // All done!
        info!("Done setting up Minecraft server!");
    }
    /// Clean up the server for the next test run.
    ///
    /// This should be called before every _run_ of tests, not _each_ test.
    fn cleanup(&self) {
        // Delete the saves directory, since we want a fresh testing world every time.
        let saves_dir = self.server_dir.clone().join("world");
        if saves_dir.exists() {
            // toss it
            if let Err(error) = std::fs::remove_dir_all(saves_dir) {
                error!("Failed to clean saves folder! Aborting testing!");
                error!("Reason: {error:#?}");
                panic!()
            }
        }
    }

    /// Starts the Minecraft server and blocks until it finishes starting.
    async fn start_and_wait(&mut self) {
        #[cfg(windows)]
        let (shell, args) = ("cmd", ["/C", "run.bat"]);
        #[cfg(not(windows))]
        let (shell, args) = ("sh", ["run.sh"]);
        let child = Command::new(shell)
            .args(args)
            .current_dir(&self.server_dir)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("Failed to run server start script");
        self.process = Some(child);
        self.scan_output(")! For help, type \"help\"").await;
        assert!(self.process.is_some())
    }

    /// Set up RCON for the server
    async fn attach_rcon(&mut self) {
        let build = <Connection<AsyncStdStream>>::builder();
        let connection = build
            .enable_minecraft_quirks(true)
            .connect(
                format!("localhost:{MINECRAFT_RCON_PORT}"), //TODO: make the address configurable
                MINECRAFT_RCON_PASSWORD,
            )
            .await
            .expect("Should be able to open rcon.");
        self.rcon_connection = Some(connection)
    }

    /// Send an RCON message.
    ///
    /// Returns `None` if rcon is not open.
    pub async fn send_rcon(&mut self, command: &str) -> Option<String> {
        if let Some(ref mut connection) = self.rcon_connection {
            let response = connection
                .cmd(command)
                .await
                .expect("rcon should not fail.");

            // we have to wait a tiny bit between every rcon command to make sure that
            // block states and stuff have time to update. So we wait just over a tick.
            std::thread::sleep(Duration::from_millis(60));

            Some(response)
        } else {
            debug!("Tried send RCON while RCON was not set up.");
            None
        }
    }

    /// Scan the output of the starting Minecraft process to wait for the server ready message.
    ///
    /// This is pub since we need to call it after all of the tests run.
    pub async fn shutdown_and_wait(&mut self) {
        // we take the process entirely since we will be killing it anyways
        let mut process = if let Some(child) = self.process.take() {
            child
        } else {
            // there is no server to shut down.
            warn!("Tried to shutdown when there was not world!");
            return;
        };

        process
            .stdin
            .as_mut()
            .expect("ditto")
            .write_all(b"/stop\n")
            .await
            .expect("Should write everything.");

        // now we wait for the server to exit.
        let status = process.wait().await.expect("Should shut down.");
        if !status.success() {
            // odd. but we still exited
            warn!("Shutdown didn't return success but did still close. So idk.")
        }
    }

    /// Looks for output from the minecraft server process, and gives up after 30 sec
    async fn scan_output(&mut self, return_on: &str) {
        #[allow(clippy::collapsible_if)] // maybe clean this up later but i like how this looks -Doc
        if let Some(child) = &mut self.process {
            if let Some(stdout) = child.stdout.take() {
                let mut reader = BufReader::new(stdout).lines();

                // max of 30 second timeout
                let res = timeout(Duration::from_secs(30), async {
                    while let Ok(Some(line)) = reader.next_line().await {
                        debug!("[Server]: {}", line);
                        if line.contains(return_on) {
                            return Ok(());
                        }
                    }
                    Err("Server closed unexpectedly")
                })
                .await;

                if res.is_err() {
                    error!("Timed out waiting for: `{}`!", return_on);
                    panic!()
                }
            }
        } else {
            // no server to scan output from?
            error!("Tried to scan output when there was no server to scan!");
            panic!()
        }
    }
}
