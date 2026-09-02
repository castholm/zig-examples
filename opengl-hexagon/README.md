<!--
SPDX-FileCopyrightText: NONE
SPDX-License-Identifier: CC0-1.0
-->

# OpenGL hexagon

Draws a colorful hexagon to the screen using SDL3 and OpenGL.

Uses [castholm/SDL](https://github.com/castholm/SDL) to build SDL3 from source and [zigglgen](https://github.com/castholm/zigglgen) to generate OpenGL bindings.

![Preview](preview.png)

## Building

Requires Zig 0.17.0-dev (master).

```sh
# Run the game
zig build run

# Cross-compile for Windows
zig build -Dtarget=x86_64-windows-gnu -Doptimize=fast

# Cross-compile for Linux
zig build -Dtarget=x86_64-linux-gnu -Doptimize=fast

# Build for the Web and serve locally (requires Emscripten)
embuilder build sysroot
zig build -Dtarget=wasm32-emscripten -Doptimize=fast "-Dsystem_include_path=$(em-config CACHE)/sysroot/include"
emrun zig-out/www/opengl_hexagon.html
```
