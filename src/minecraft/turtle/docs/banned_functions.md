# Banned functions
Some of the build-in functions must NOT be called from most code.

# ALL `turtle.xyz` functions
Using any of the direct turtle commands (such as `turtle.forward()`) is disallowed, since we need to track all of the movement for [walkback](./walkback.md), and keep track of all the blocks we have seen. All methods that are available on turtle are also available through `walkback`