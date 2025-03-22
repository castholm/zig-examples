<!--
SPDX-FileCopyrightText: NONE
SPDX-License-Identifier: CC0-1.0
-->

# Snake

[SDL's example Snake game](https://examples.libsdl.org/SDL3/demo/01-snake/), written in C, built using the Zig build system.

Uses [castholm/SDL](https://github.com/castholm/SDL) to build SDL3 from source.

![Preview](preview.gif)

## Building

Requires Zig 0.14.0 or 0.15.0-dev (master).

```sh
# Run the game
zig build run

# Cross-compile for Windows
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast

# Cross-compile for Linux
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast

# Build for the Web (requires Emscripten)
embuilder build sysroot
zig build -Dtarget=wasm32-emscripten-none -Doptimize=ReleaseFast --sysroot "$(em-config CACHE)/sysroot"
```
