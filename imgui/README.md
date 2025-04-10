<!--
© 2024 Carl Åstholm
SPDX-License-Identifier: MIT
-->

# ImGui

Demonstrates integrating ImGui using the SDL3 backend.

The build does not work for wasm32-emscripten-none failing at the link step.
```sh
wasm-ld: error: ~/zig-examples/imgui/.zig-cache/o/8a796ab18c5dd51def36cd228a9b9f37/libimgui.a(~/zig-examples/imgui/.zig-cache/o/79254e1ef1366a43ec6946b90686bf15/application.o): undefined symbol: typeinfo for std::__1::bad_function_call
wasm-ld: error: ~/zig-examples/imgui/.zig-cache/o/8a796ab18c5dd51def36cd228a9b9f37/libimgui.a(~/zig-examples/imgui/.zig-cache/o/79254e1ef1366a43ec6946b90686bf15/application.o): undefined symbol: std::__1::bad_function_call::~bad_function_call()
wasm-ld: error: ~/zig-examples/imgui/.zig-cache/o/8a796ab18c5dd51def36cd228a9b9f37/libimgui.a(~/zig-examples/imgui/.zig-cache/o/79254e1ef1366a43ec6946b90686bf15/application.o): undefined symbol: vtable for std::__1::bad_function_call
```

Uses [castholm/SDL](https://github.com/castholm/SDL) to build SDL3 from source.

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
