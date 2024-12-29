<!--
SPDX-FileCopyrightText: NONE
SPDX-License-Identifier: CC0-1.0
-->

# C/C++/Zig

Demonstrates how to compile a program consisting of a mix of C, C++ and Zig code.

```
Entered main.c
Hello from C!
Hello from C++!
Hello from Zig!
Leaving main.c
```

## Building

Requires Zig `0.12.1`, `0.13.0` or `0.14.0-dev` (master).

```sh
# Build/run the app using the C entry point
zig build run -Dmain=c

# Build/run the app using the C++ entry point
zig build run -Dmain=cpp

# Build/run the app using the Zig entry point
zig build run -Dmain=zig
```
