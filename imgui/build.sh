#!/bin/bash

# This builds the websocket client example. Requires that emsdk is installed and available on PATH.
# In order to run the example fully, you must
# 1. ./web_example_client_build.sh
# 2. pun python -m http.server 8888 -d build/web
# 3. pun python examples/echo.py

mkdir -p build/web

IMGUI_PATH=imgui
IMGUI_INCLUDE=$IMGUI_PATH/include

# Assume SDL was build separately using CMake:
# Clone SDL3 and change into the directory.
# mkdir build-wasm && cd build-wasm
# emcmake cmake -G Ninja -B build -S .. -DCMAKE_INSTALL_PREFIX=./install
# ninja -C build install
SDL_PATH=third-party/SDL/build-wasm/install

# Ideally we'd do everything with just zig.
# zig build -Dtarget=wasm32-emscripten-none --sysroot /opt/emsdk/upstream/emscripten/cache/sysroot

emcc main.cpp application.cpp \
${IMGUI_PATH}/src/imgui_demo.cpp \
${IMGUI_PATH}/src/imgui_draw.cpp \
${IMGUI_PATH}/src/imgui_impl_sdl3.cpp \
${IMGUI_PATH}/src/imgui_impl_sdlgpu3.cpp \
${IMGUI_PATH}/src/imgui_impl_sdlrenderer3.cpp \
${IMGUI_PATH}/src/imgui_tables.cpp \
${IMGUI_PATH}/src/imgui_widgets.cpp \
${IMGUI_PATH}/src/imgui.cpp \
-o build/web/index.js \
-s WASM=1 \
-fsanitize=undefined \
-I${IMGUI_INCLUDE} \
-I${SDL_PATH}/include \
-L${SDL_PATH}/lib \
-lSDL3
