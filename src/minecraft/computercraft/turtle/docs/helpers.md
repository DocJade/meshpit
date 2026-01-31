# Helper functions intro
Some functions are commonly duplicated between different turtle task code, so they are contained within a submodule.

# Available functions
### `helper.assert()`
This is analogous to `assert!()` in Rust, and will call the [panic handler](./panicking.md) if the input is either `nil` or `false`.