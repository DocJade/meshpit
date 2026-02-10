<h1 align="center">
  <br>
  <img src="https://github.com/DocJade/meshpit/blob/master/img/MeshpitLogo.png?raw=true" alt="Meshpit" width="256">
  <br>
  Meshpit
  <br>
</h1>

<h3 align="center">A self-replicating CC:Tweaked turtle swarm.</h4>

<p align="center">
  <img alt="Blazingly fast!" src="https://img.shields.io/badge/Blazingly_fast!-000000?logo=rust&logoColor=white">
	<img alt="One indexed!" src="https://img.shields.io/badge/One_indexed!-000080?logo=lua&logoColor=white">
  <a href="https://kofi.docjade.com/">
    <img alt="Support me on Ko-fi!" src="https://img.shields.io/badge/Support%20me%20on%20Ko--fi!-FF5E5B?logo=ko-fi&logoColor=white">
  </a>
  <a href="https://en.wikipedia.org/wiki/Asbestos">
		<img alt="Asbestos free!" src="https://img.shields.io/badge/Asbestos_free!-purple">
	</a>
</p>

<p align="center">
	<a href="#overview">Overview</a> •
  <a href="#features">Features</a> •
  <a href="#planned-features">Planned features</a> •
  <a href="#credits">Credits</a>
</p>

## Overview
Meshpit is a turtle swarm controller for CC:Tweaked Turtles with the goal of completly conquoring Minecraft fully atonomously, while also looking cool as hell.

## Features
* LUA: A nicer `walkback` wrapper on every `turtle` call, simplifying the API. `walkback` also does the following:
  * Keep track of seen turtle positions, including an additional set of API calls that allow turtles to step backwards through their previous positions to rewind movement
  * Keep track of seen blocks, allowing turtles to keep track of what they have seen, and where. Will be used in the future for pathfinding and for reporting world state back to the control server.
  * Adds "scanning" movements that allow the turtle to document every block its seen along a path.
  * Some other stuff i forgot
* RUST: A Rust-based test Minecraft test-harness
  * Currently just tests the underlying lua implementations. In the future this will be expanded to a wider variety of real-ish world tests.
  * This test harness will automatically install a NeoForge Minecraft server, download mods, configure, and run the Minecraft server for tests automagically!
* A Client/Server model between lua and Rust, allowing me to avoid writing Lua for anything complicated. Lua sucks.

and probably more stuff I can't be bothered to write down at 1am.

## Planned features
- [ ] Automatic task delegation to Turtles from a Rust-based webserver
- [ ] More planned features
- [ ] serously, just look at the open issues

## Credits
- [DocJade](https://github.com/DocJade)
  - [YouTube](https://www.youtube.com/@DocJade)
  - Came up with the idea.
- [Dr.Cats](https://github.com/mr-cats)
  - Logo concept, final logo assembled by DocJade.
  - Emotional support.
- [CC:Tweaked](https://github.com/cc-tweaked/CC-Tweaked)
  - The excellent modern fork of the original ComputerCraft Minecraft mod.
- [Lua](https://www.lua.org/)
  - Begrudgingly, only here since it's the language of choice in ComputerCraft.
- [Rust](https://rust-lang.org/)
  - Written in Rust, since Rust is awesome.
