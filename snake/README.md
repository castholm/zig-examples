<!--
SPDX-FileCopyrightText: NONE
SPDX-License-Identifier: CC0-1.0
-->

# Snake

[SDL's example Snake game](https://examples.libsdl.org/SDL3/demo/01-snake/), written in C, built using the Zig build system.

Uses the [castholm/SDL](https://github.com/castholm/SDL) Zig package, which builds SDL3 from source using the Zig build system.

![Preview](preview.gif)

## Building

Requires Zig `0.14.0` or `0.15.0-dev` (master).

```sh
# Run the game
zig build run

# Cross-compile for Windows
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast

# Cross-compile for Linux
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast
```
