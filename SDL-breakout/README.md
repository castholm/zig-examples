<!--
© 2024 Carl Åstholm
SPDX-License-Identifier: MIT
-->

# SDL-breakout

Simple Breakout clone using SDL3 for windowing, audio, input, etc.

Uses the [castholm/SDL](https://github.com/castholm/SDL) port of SDL3 to the Zig build system.

How quickly can you break all the bricks?

![Preview](preview.gif)

## Controls

### Mouse/keyboard

- Left mouse button: Lock the mouse to the game window
- Mouse, arrow keys: Move the paddle
- Left shift: Hold to slow the paddle movement
- Left mouse button, space: Launch the ball
- R: Restart
- Esc: Unlock the mouse

### Gamepad

- D-pad, left stick: Move the paddle
- LB, RB, LT, RT: Hold to slow the paddle movement
- A, B: Launch the ball
- Start, back: Restart

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

## Additional credits

- Sprites: [Puzzle Pack 1.0](https://www.kenney.nl/assets/puzzle-pack) by [Kenney](https://www.kenney.nl/), licensed under CC0
- Sounds: [Interface Sounds 1.0](https://www.kenney.nl/assets/interface-sounds) by [Kenney](https://www.kenney.nl/), licensed under CC0
