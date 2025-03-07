<!--
© 2024 Carl Åstholm
SPDX-License-Identifier: MIT
-->

# Zig example projects

This is my collection of small example projects showcasing the Zig language, build system and ecosystem.

- [Breakout](#breakout)
- [Snake](#snake)
- [OpenGL (SDL)](#opengl-sdl)
- [C/C++/Zig](#cczig)

## [Breakout](breakout)

Simple Breakout clone using SDL3 for video, audio, input, etc. How quickly can you break all the bricks?

![Preview](breakout/preview.gif)

## [Snake](snake)

[SDL's example Snake game](https://examples.libsdl.org/SDL3/demo/01-snake/), written in C, built using the Zig build system.

![Preview](snake/preview.gif)

## [OpenGL (SDL)](opengl-sdl)

Creates a window using SDL3, then draws to it using OpenGL bindings generated by [zigglgen](https://github.com/castholm/zigglgen).

![Preview](opengl-sdl/preview.png)

## [C/C++/Zig](c-cpp-zig)

Demonstrates how to compile a program consisting of a mix of C, C++ and Zig code.

```
Entered main.c
Hello from C!
Hello from C++!
Hello from Zig!
Leaving main.c
```
