<!--
© 2024 Carl Åstholm
SPDX-License-Identifier: MIT
-->

# SDL-snake

[SDL's own example Snake game](https://examples.libsdl.org/SDL3/demo/01-snake/) written in C, built using the Zig build system.

Uses the [castholm/SDL](https://github.com/castholm/SDL) Zig package, which builds SDL3 from source using the Zig build system.

![Preview](preview.gif)

## Building

Requires Zig `0.12.1`, `0.13.0` or `0.14.0-dev`.

```sh
# Run the game
zig build run

# Build the game for Windows
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast

# Build the game for Linux
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast
```
