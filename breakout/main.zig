// © 2024 Carl Åstholm
// SPDX-License-Identifier: MIT

const std = @import("std");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
});

const post_writergate = @hasDecl(std, "Io"); // TODO: Remove after 0.15 (also audit std.Io.Writer code)

pub const std_options: std.Options = .{ .log_level = .debug };

const sdl_log = std.log.scoped(.sdl);
const app_log = std.log.scoped(.app);

const sprites = struct {
    const bmp = @embedFile("sprites.bmp");

    // zig fmt: off
    const brick_2x1_purple: c.SDL_FRect = .{ .x =   1, .y =  1, .w = 64, .h = 32 };
    const brick_1x1_purple: c.SDL_FRect = .{ .x =  67, .y =  1, .w = 32, .h = 32 };
    const brick_2x1_red:    c.SDL_FRect = .{ .x = 101, .y =  1, .w = 64, .h = 32 };
    const brick_1x1_red:    c.SDL_FRect = .{ .x = 167, .y =  1, .w = 32, .h = 32 };
    const brick_2x1_yellow: c.SDL_FRect = .{ .x =   1, .y = 35, .w = 64, .h = 32 };
    const brick_1x1_yellow: c.SDL_FRect = .{ .x =  67, .y = 35, .w = 32, .h = 32 };
    const brick_2x1_green:  c.SDL_FRect = .{ .x = 101, .y = 35, .w = 64, .h = 32 };
    const brick_1x1_green:  c.SDL_FRect = .{ .x = 167, .y = 35, .w = 32, .h = 32 };
    const brick_2x1_blue:   c.SDL_FRect = .{ .x =   1, .y = 69, .w = 64, .h = 32 };
    const brick_1x1_blue:   c.SDL_FRect = .{ .x =  67, .y = 69, .w = 32, .h = 32 };
    const brick_2x1_gray:   c.SDL_FRect = .{ .x = 101, .y = 69, .w = 64, .h = 32 };
    const brick_1x1_gray:   c.SDL_FRect = .{ .x = 167, .y = 69, .w = 32, .h = 32 };

    const ball:   c.SDL_FRect = .{ .x =  2, .y = 104, .w =  22, .h = 22 };
    const paddle: c.SDL_FRect = .{ .x = 27, .y = 103, .w = 104, .h = 24 };
    // zig fmt: on
};

const sounds = struct {
    const wav = @embedFile("sounds.wav");

    // zig fmt: off
    const hit_wall   = .{      0,  4_886 };
    const hit_paddle = .{  4_886, 17_165 };
    const hit_brick  = .{ 17_165, 25_592 };
    const win        = .{ 25_592, 49_362 };
    const lose       = .{ 49_362, 64_024 };
    // zig fmt: on
};

var fully_initialized = false;

const window_w = 640;
const window_h = 480;
var window: *c.SDL_Window = undefined;
var renderer: *c.SDL_Renderer = undefined;

var sprites_texture: *c.SDL_Texture = undefined;

var sounds_spec: c.SDL_AudioSpec = undefined;
var sounds_data: []u8 = undefined;

var audio_device: c.SDL_AudioDeviceID = undefined;

var audio_streams_buf: [8]*c.SDL_AudioStream = undefined;
var audio_streams: []*c.SDL_AudioStream = audio_streams_buf[0..0];

var gamepad: ?*c.SDL_Gamepad = undefined;

var phcon: PhysicalControllerState = undefined;
var prev_phcon: PhysicalControllerState = undefined;
var vcon: VirtualControllerState = undefined;
var prev_vcon: VirtualControllerState = undefined;

var best_score: u32 = undefined;

var timekeeper: Timekeeper = undefined;

var paddle: Paddle = undefined;
var ball: Ball = undefined;
var bricks: std.BoundedArray(Brick, 100) = undefined;

var score: u32 = undefined;
var score_color: [3]u8 = undefined;

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    sdl_log.debug("SDL build time version: {d}.{d}.{d}", .{
        c.SDL_MAJOR_VERSION,
        c.SDL_MINOR_VERSION,
        c.SDL_MICRO_VERSION,
    });
    sdl_log.debug("SDL build time revision: {s}", .{c.SDL_REVISION});
    {
        const version = c.SDL_GetVersion();
        sdl_log.debug("SDL runtime version: {d}.{d}.{d}", .{
            c.SDL_VERSIONNUM_MAJOR(version),
            c.SDL_VERSIONNUM_MINOR(version),
            c.SDL_VERSIONNUM_MICRO(version),
        });
        const revision: [*:0]const u8 = c.SDL_GetRevision();
        sdl_log.debug("SDL runtime revision: {s}", .{revision});
    }

    try errify(c.SDL_SetAppMetadata("Speedbreaker", "0.0.0", "example.zig-examples.breakout"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMEPAD));
    // We don't need to call 'SDL_Quit()' when using main callbacks.

    sdl_log.debug("SDL video drivers: {f}", .{fmtSdlDrivers(
        c.SDL_GetCurrentVideoDriver().?,
        c.SDL_GetNumVideoDrivers(),
        c.SDL_GetVideoDriver,
    )});
    sdl_log.debug("SDL audio drivers: {f}", .{fmtSdlDrivers(
        c.SDL_GetCurrentAudioDriver().?,
        c.SDL_GetNumAudioDrivers(),
        c.SDL_GetAudioDriver,
    )});

    errify(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};

    try errify(c.SDL_CreateWindowAndRenderer("Speedbreaker", window_w, window_h, 0, @ptrCast(&window), @ptrCast(&renderer)));
    errdefer c.SDL_DestroyWindow(window);
    errdefer c.SDL_DestroyRenderer(renderer);

    sdl_log.debug("SDL render drivers: {f}", .{fmtSdlDrivers(
        c.SDL_GetRendererName(renderer).?,
        c.SDL_GetNumRenderDrivers(),
        c.SDL_GetRenderDriver,
    )});

    {
        const stream: *c.SDL_IOStream = try errify(c.SDL_IOFromConstMem(sprites.bmp, sprites.bmp.len));
        const surface: *c.SDL_Surface = try errify(c.SDL_LoadBMP_IO(stream, true));
        defer c.SDL_DestroySurface(surface);

        sprites_texture = try errify(c.SDL_CreateTextureFromSurface(renderer, surface));
        errdefer comptime unreachable;
    }
    errdefer c.SDL_DestroyTexture(sprites_texture);

    {
        const stream: *c.SDL_IOStream = try errify(c.SDL_IOFromConstMem(sounds.wav, sounds.wav.len));
        var data_ptr: ?[*]u8 = undefined;
        var data_len: u32 = undefined;
        try errify(c.SDL_LoadWAV_IO(stream, true, &sounds_spec, &data_ptr, &data_len));
        errdefer comptime unreachable;

        sounds_data = data_ptr.?[0..data_len];
    }
    errdefer c.SDL_free(sounds_data.ptr);

    audio_device = try errify(c.SDL_OpenAudioDevice(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &sounds_spec));
    errdefer c.SDL_CloseAudioDevice(audio_device);

    errdefer while (audio_streams.len != 0) {
        c.SDL_DestroyAudioStream(audio_streams[audio_streams.len - 1]);
        audio_streams.len -= 1;
    };
    while (audio_streams.len < audio_streams_buf.len) {
        audio_streams.len += 1;
        audio_streams[audio_streams.len - 1] = try errify(c.SDL_CreateAudioStream(&sounds_spec, null));
    }

    try errify(c.SDL_BindAudioStreams(audio_device, @ptrCast(audio_streams.ptr), @intCast(audio_streams.len)));

    {
        var count: c_int = 0;
        const gamepads: [*]c.SDL_JoystickID = try errify(c.SDL_GetGamepads(&count));
        defer c.SDL_free(gamepads);

        gamepad = if (count > 0) try errify(c.SDL_OpenGamepad(gamepads[0])) else null;
    }
    errdefer c.SDL_CloseGamepad(gamepad);

    phcon = .{};
    prev_phcon = phcon;
    vcon = .{};
    prev_vcon = vcon;

    try loadBestScore();

    timekeeper = .{ .tocks_per_s = c.SDL_GetPerformanceFrequency() };

    try resetGame();

    fully_initialized = true;
    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn resetGame() !void {
    paddle = .{
        .box = .{
            .x = window_w * 0.5 - sprites.paddle.w * 0.5,
            .y = window_h - sprites.paddle.h,
            .w = sprites.paddle.w,
            .h = sprites.paddle.h,
        },
        .src_rect = &sprites.paddle,
    };

    ball = .{
        .box = .{
            .x = paddle.box.x + paddle.box.w * 0.5,
            .y = paddle.box.y - sprites.ball.h,
            .w = sprites.ball.w,
            .h = sprites.ball.h,
        },
        .vel_x = 0,
        .vel_y = 0,
        .launched = false,
        .src_rect = &sprites.ball,
    };

    bricks = .{};
    {
        const x = window_w * 0.5;
        const h = sprites.brick_1x1_gray.h;
        const gap = 5;
        for ([_][2]*const c.SDL_FRect{
            .{ &sprites.brick_1x1_purple, &sprites.brick_2x1_purple },
            .{ &sprites.brick_1x1_red, &sprites.brick_2x1_red },
            .{ &sprites.brick_1x1_yellow, &sprites.brick_2x1_yellow },
            .{ &sprites.brick_1x1_green, &sprites.brick_2x1_green },
            .{ &sprites.brick_1x1_blue, &sprites.brick_2x1_blue },
            .{ &sprites.brick_1x1_gray, &sprites.brick_2x1_gray },
        }, 0..) |src_rects, row| {
            const y = gap + (h + gap) * (@as(f32, @floatFromInt(row)) + 1);
            var large = row % 2 == 0;
            var src_rect = src_rects[@intFromBool(large)];
            try bricks.append(.{
                .box = .{
                    .x = x - src_rect.w * 0.5,
                    .y = y,
                    .w = src_rect.w,
                    .h = src_rect.h,
                },
                .src_rect = src_rect,
            });
            var rel_x: f32 = 0;
            var count: usize = 0;
            while (count < 4) : (count += 1) {
                rel_x += src_rect.w * 0.5 + gap;
                large = !large;
                src_rect = src_rects[@intFromBool(large)];
                rel_x += src_rect.w * 0.5;
                for ([_]f32{ -1, 1 }) |sign| {
                    try bricks.append(.{
                        .box = .{
                            .x = x - src_rect.w * 0.5 + rel_x * sign,
                            .y = y,
                            .w = src_rect.w,
                            .h = src_rect.h,
                        },
                        .src_rect = src_rect,
                    });
                }
            }
        }
    }

    score = 0;
    score_color = .{ 0xff, 0xff, 0xff };
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    var sounds_to_play: std.EnumSet(enum {
        hit_wall,
        hit_paddle,
        hit_brick,
        win,
        lose,
    }) = .initEmpty();

    var won = false;

    // Update the game state.
    while (timekeeper.consume()) {
        // Map the physical controller state to the virtual controller state.

        prev_vcon = vcon;
        vcon.move_paddle_exact = 0;

        vcon.move_paddle_left =
            phcon.k_left or
            phcon.g_left or
            phcon.g_leftx <= -0x4000;
        vcon.move_paddle_right =
            phcon.k_right or
            phcon.g_right or
            phcon.g_leftx >= 0x4000;
        vcon.slow_paddle_movement =
            phcon.k_lshift or
            phcon.g_left_shoulder or
            phcon.g_right_shoulder or
            phcon.g_left_trigger >= 0x2000 or
            phcon.g_right_trigger >= 0x2000;
        vcon.launch_ball =
            phcon.k_space or
            phcon.g_south or
            phcon.g_east;
        vcon.reset_game =
            phcon.k_r or
            phcon.g_back or
            phcon.g_start;

        if (!vcon.lock_mouse) {
            if (phcon.m_left and !prev_phcon.m_left) {
                vcon.lock_mouse = true;
                try errify(c.SDL_SetWindowRelativeMouseMode(window, true));
            }
        } else {
            if (phcon.k_escape and !prev_phcon.k_escape) {
                vcon.lock_mouse = false;
                try errify(c.SDL_SetWindowRelativeMouseMode(window, false));
            } else {
                vcon.launch_ball = vcon.launch_ball or phcon.m_left;
                vcon.move_paddle_exact = phcon.m_xrel;
            }
        }

        prev_phcon = phcon;
        phcon.m_xrel = 0;

        if (vcon.reset_game and !prev_vcon.reset_game) {
            try resetGame();
            return c.SDL_APP_CONTINUE;
        }

        // Move the paddle.
        {
            var paddle_vel_x: f32 = 0;
            var keyboard_gamepad_vel_x: f32 = 0;
            if (vcon.move_paddle_left) keyboard_gamepad_vel_x -= 10;
            if (vcon.move_paddle_right) keyboard_gamepad_vel_x += 10;
            if (vcon.slow_paddle_movement) keyboard_gamepad_vel_x *= 0.5;
            paddle_vel_x += keyboard_gamepad_vel_x;
            var mouse_vel_x = vcon.move_paddle_exact;
            if (vcon.slow_paddle_movement) mouse_vel_x *= 0.25;
            paddle_vel_x += mouse_vel_x;
            paddle.box.x = std.math.clamp(paddle.box.x + paddle_vel_x, 0, window_w - paddle.box.w);
        }

        const previous_ball_y = ball.box.y;

        if (!ball.launched) {
            // Stick the ball to the paddle.
            ball.box.x = paddle.box.x + paddle.box.w * 0.5;

            if (vcon.launch_ball and !prev_vcon.launch_ball) {
                // Launch the ball.
                const angle = ball.getPaddleBounceAngle(paddle);
                ball.vel_x = @cos(angle) * 4;
                ball.vel_y = @sin(angle) * 4;
                ball.launched = true;
            }
        }

        if (ball.launched) {
            // Check for and handle collisions using swept AABB collision detection.
            var remaining_vel_x: f32 = ball.vel_x;
            var remaining_vel_y: f32 = ball.vel_y;
            while (remaining_vel_x != 0 or remaining_vel_y != 0) {
                var t: f32 = 1;
                var sign_x: f32 = 0;
                var sign_y: f32 = 0;
                var collidee: union(enum) {
                    none: void,
                    wall: void,
                    paddle: void,
                    brick: usize,
                } = .none;

                const remaining_vel_x_inv = 1 / remaining_vel_x;
                const remaining_vel_y_inv = 1 / remaining_vel_y;

                if (remaining_vel_x < 0) {
                    // Left wall
                    const wall_t = -ball.box.x * remaining_vel_x_inv;
                    if (t - wall_t >= 0.001) {
                        t = wall_t;
                        sign_x = 1;
                        collidee = .wall;
                    }
                } else if (remaining_vel_x > 0) {
                    // Right wall
                    const wall_t = (window_w - ball.box.w - ball.box.x) * remaining_vel_x_inv;
                    if (t - wall_t >= 0.001) {
                        t = wall_t;
                        sign_x = -1;
                        collidee = .wall;
                    }
                }
                if (remaining_vel_y < 0) {
                    // Top wall
                    const wall_t = -ball.box.y * remaining_vel_y_inv;
                    if (t - wall_t >= 0.001) {
                        t = wall_t;
                        sign_y = 1;
                        collidee = .wall;
                    }
                } else if (remaining_vel_y > 0) {
                    // Paddle
                    const paddle_top: Box = .{
                        .x = paddle.box.x,
                        .y = paddle.box.y,
                        .w = paddle.box.w,
                        .h = 0,
                    };
                    if (ball.box.sweepTest(remaining_vel_x, remaining_vel_y, paddle_top, 0, 0)) |collision| {
                        if (t - collision.t >= 0.001) {
                            t = @min(0, collision.t);
                            sign_y = -1;
                            collidee = .paddle;
                        }
                    }
                }

                // Bricks
                const broad: Box = .{
                    .x = @min(ball.box.x, ball.box.x + remaining_vel_x),
                    .y = @min(ball.box.y, ball.box.y + remaining_vel_y),
                    .w = @max(ball.box.w, ball.box.w + remaining_vel_x),
                    .h = @max(ball.box.h, ball.box.h + remaining_vel_y),
                };
                for (bricks.slice(), 0..) |brick, i| {
                    if (broad.intersects(brick.box)) {
                        if (ball.box.sweepTest(remaining_vel_x, remaining_vel_y, brick.box, 0, 0)) |collision| {
                            if (t - collision.t >= 0.001) {
                                t = collision.t;
                                sign_x = collision.sign_x;
                                sign_y = collision.sign_y;
                                collidee = .{ .brick = i };
                            }
                        }
                    }
                }

                // Bounce the ball off the object it collided with (if any).
                if (collidee == .paddle) {
                    const angle = ball.getPaddleBounceAngle(paddle);
                    const vel_factor = 1.05;
                    ball.box.x += remaining_vel_x * t;
                    ball.box.y += remaining_vel_y * t;
                    const vel = @sqrt(ball.vel_x * ball.vel_x + ball.vel_y * ball.vel_y) * vel_factor;
                    ball.vel_x = @cos(angle) * vel;
                    ball.vel_y = @sin(angle) * vel;
                    remaining_vel_x *= (1 - t);
                    remaining_vel_y *= (1 - t);
                    const remaining_vel = @sqrt(remaining_vel_x * remaining_vel_x + remaining_vel_y * remaining_vel_y) * vel_factor;
                    remaining_vel_x = @cos(angle) * remaining_vel;
                    remaining_vel_y = @sin(angle) * remaining_vel;
                } else {
                    ball.box.x += remaining_vel_x * t;
                    ball.box.y += remaining_vel_y * t;
                    ball.vel_x = std.math.copysign(ball.vel_x, if (sign_x != 0) sign_x else remaining_vel_x);
                    ball.vel_y = std.math.copysign(ball.vel_y, if (sign_y != 0) sign_y else remaining_vel_y);
                    remaining_vel_x = std.math.copysign(remaining_vel_x * (1 - t), ball.vel_x);
                    remaining_vel_y = std.math.copysign(remaining_vel_y * (1 - t), ball.vel_y);
                    if (collidee == .brick) {
                        _ = bricks.swapRemove(collidee.brick);
                    }
                }

                // Enqueue an appropriate sound effect.
                switch (collidee) {
                    .wall => {
                        if (ball.box.y < window_h) {
                            sounds_to_play.insert(.hit_wall);
                        }
                    },
                    .paddle => {
                        sounds_to_play.insert(.hit_paddle);
                    },
                    .brick => {
                        if (bricks.len == 0) {
                            won = true;
                            sounds_to_play.insert(.win);
                        } else {
                            sounds_to_play.insert(.hit_brick);
                        }
                    },
                    .none => {},
                }
            }
        }

        if (previous_ball_y < window_h and ball.box.y >= window_h) {
            // The ball fell below the paddle.
            if (bricks.len != 0) {
                sounds_to_play.insert(.lose);
            }
        }

        // Update score.
        if (ball.launched) {
            if (ball.box.y < window_h) {
                if (bricks.len != 0) {
                    score +|= 1;
                } else {
                    best_score = @min(score, best_score);
                }
            }
            if (score <= best_score and bricks.len == 0) {
                score_color = .{ 0x52, 0xcc, 0x73 };
            } else if (ball.box.y >= window_h or score > best_score) {
                score_color = .{ 0xcc, 0x5c, 0x52 };
            }
        }
    }

    // Save score.
    if (won and score < best_score) {
        try saveBestScore();
    }

    // Play audio.
    {
        // We have created eight SDL audio streams. When we want to play a sound effect,
        // we loop through the streams for the first one that isn't playing any audio
        // and write the audio to that stream.
        // This is a kind of stupid and naive way of handling audio, but it's very easy to
        // set up and use. A proper program would probably use an audio mixing callback.
        var stream_index: usize = 0;
        var it = sounds_to_play.iterator();
        iterate_sounds: while (it.next()) |sound| {
            const stream = find_available_stream: while (stream_index < audio_streams.len) {
                defer stream_index += 1;
                const stream = audio_streams[stream_index];
                if (try errify(c.SDL_GetAudioStreamAvailable(stream)) == 0) {
                    break :find_available_stream stream;
                }
            } else {
                break :iterate_sounds;
            };
            const frame_size: usize = c.SDL_AUDIO_BYTESIZE(sounds_spec.format) * @as(c_uint, @intCast(sounds_spec.channels));
            const start: usize, const end: usize = switch (sound) {
                .hit_wall => sounds.hit_wall,
                .hit_paddle => sounds.hit_paddle,
                .hit_brick => sounds.hit_brick,
                .win => sounds.win,
                .lose => sounds.lose,
            };
            const data = sounds_data[(frame_size * start)..(frame_size * end)];
            try errify(c.SDL_PutAudioStreamData(stream, data.ptr, @intCast(data.len)));
        }
    }

    // Draw.
    {
        try errify(c.SDL_SetRenderDrawColor(renderer, 0x47, 0x5b, 0x8d, 0xff));

        try errify(c.SDL_RenderClear(renderer));

        for (bricks.slice()) |brick| try renderObject(renderer, sprites_texture, brick.src_rect, brick.box);
        try renderObject(renderer, sprites_texture, ball.src_rect, ball.box);
        try renderObject(renderer, sprites_texture, paddle.src_rect, paddle.box);

        try errify(c.SDL_SetRenderScale(renderer, 2, 2));
        {
            var buf: [12]u8 = undefined;
            var time: f32 = @min(@as(f32, @floatFromInt(score)) / Timekeeper.updates_per_s, 99.999);
            var text = try std.fmt.bufPrintZ(&buf, "TIME {d:0>6.3}", .{time});
            try errify(c.SDL_SetRenderDrawColor(renderer, score_color[0], score_color[1], score_color[2], 0xff));
            try errify(c.SDL_RenderDebugText(renderer, 8, 8, text.ptr));
            time = @min(@as(f32, @floatFromInt(best_score)) / Timekeeper.updates_per_s, 99.999);
            text = try std.fmt.bufPrintZ(&buf, "BEST {d:0>6.3}", .{time});
            try errify(c.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff));
            try errify(c.SDL_RenderDebugText(renderer, window_w / 2 - 8 * 12, 8, text.ptr));
        }
        try errify(c.SDL_SetRenderScale(renderer, 1, 1));

        try errify(c.SDL_RenderPresent(renderer));
    }

    timekeeper.produce(c.SDL_GetPerformanceCounter());

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
            const down = event.type == c.SDL_EVENT_KEY_DOWN;
            switch (event.key.scancode) {
                c.SDL_SCANCODE_LEFT => phcon.k_left = down,
                c.SDL_SCANCODE_RIGHT => phcon.k_right = down,
                c.SDL_SCANCODE_LSHIFT => phcon.k_lshift = down,
                c.SDL_SCANCODE_SPACE => phcon.k_space = down,
                c.SDL_SCANCODE_R => phcon.k_r = down,
                c.SDL_SCANCODE_ESCAPE => phcon.k_escape = down,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
            const down = event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN;
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => phcon.m_left = down,
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            phcon.m_xrel += event.motion.xrel;
        },
        c.SDL_EVENT_GAMEPAD_ADDED => {
            if (gamepad == null) {
                gamepad = try errify(c.SDL_OpenGamepad(event.gdevice.which));
            }
        },
        c.SDL_EVENT_GAMEPAD_REMOVED => {
            if (gamepad != null) {
                c.SDL_CloseGamepad(gamepad);
                gamepad = null;
            }
        },
        c.SDL_EVENT_GAMEPAD_BUTTON_DOWN, c.SDL_EVENT_GAMEPAD_BUTTON_UP => {
            const down = event.type == c.SDL_EVENT_GAMEPAD_BUTTON_DOWN;
            switch (event.gbutton.button) {
                c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => phcon.g_left = down,
                c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => phcon.g_right = down,
                c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER => phcon.g_left_shoulder = down,
                c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER => phcon.g_right_shoulder = down,
                c.SDL_GAMEPAD_BUTTON_SOUTH => phcon.g_south = down,
                c.SDL_GAMEPAD_BUTTON_EAST => phcon.g_east = down,
                c.SDL_GAMEPAD_BUTTON_BACK => phcon.g_back = down,
                c.SDL_GAMEPAD_BUTTON_START => phcon.g_start = down,
                else => {},
            }
        },
        c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
            switch (event.gaxis.axis) {
                c.SDL_GAMEPAD_AXIS_LEFTX => phcon.g_leftx = event.gaxis.value,
                c.SDL_GAMEPAD_AXIS_LEFT_TRIGGER => phcon.g_left_trigger = event.gaxis.value,
                c.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER => phcon.g_right_trigger = event.gaxis.value,
                else => {},
            }
        },
        else => {},
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = appstate;

    _ = result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };

    if (fully_initialized) {
        c.SDL_CloseGamepad(gamepad);
        while (audio_streams.len != 0) {
            c.SDL_DestroyAudioStream(audio_streams[audio_streams.len - 1]);
            audio_streams.len -= 1;
        }
        c.SDL_CloseAudioDevice(audio_device);
        c.SDL_free(sounds_data.ptr);
        c.SDL_DestroyTexture(sprites_texture);
        c.SDL_DestroyRenderer(renderer);
        c.SDL_DestroyWindow(window);
        fully_initialized = false;
    }
}

const Box = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn intersects(a: Box, b: Box) bool {
        const min_x = b.x - a.w;
        const max_x = b.x + b.w;
        if (a.x > min_x and a.x < max_x) {
            const min_y = b.y - a.h;
            const max_y = b.y + b.h;
            if (a.y > min_y and a.y < max_y) {
                return true;
            }
        }
        return false;
    }

    fn sweepTest(a: Box, a_vel_x: f32, a_vel_y: f32, b: Box, b_vel_x: f32, b_vel_y: f32) ?Collision {
        const vel_x_inv = 1 / (a_vel_x - b_vel_x);
        const vel_y_inv = 1 / (a_vel_y - b_vel_y);
        const min_x = b.x - a.w;
        const min_y = b.y - a.h;
        const max_x = b.x + b.w;
        const max_y = b.y + b.h;
        const t_min_x = (min_x - a.x) * vel_x_inv;
        const t_min_y = (min_y - a.y) * vel_y_inv;
        const t_max_x = (max_x - a.x) * vel_x_inv;
        const t_max_y = (max_y - a.y) * vel_y_inv;
        const entry_x = @min(t_min_x, t_max_x);
        const entry_y = @min(t_min_y, t_max_y);
        const exit_x = @max(t_min_x, t_max_x);
        const exit_y = @max(t_min_y, t_max_y);

        const last_entry = @max(entry_x, entry_y);
        const first_exit = @min(exit_x, exit_y);
        if (last_entry < first_exit and last_entry < 1 and first_exit > 0) {
            var sign_x: f32 = 0;
            var sign_y: f32 = 0;
            sign_x -= @floatFromInt(@intFromBool(last_entry == t_min_x));
            sign_x += @floatFromInt(@intFromBool(last_entry == t_max_x));
            sign_y -= @floatFromInt(@intFromBool(last_entry == t_min_y));
            sign_y += @floatFromInt(@intFromBool(last_entry == t_max_y));
            return .{ .t = last_entry, .sign_x = sign_x, .sign_y = sign_y };
        }
        return null;
    }

    const Collision = struct {
        t: f32,
        sign_x: f32,
        sign_y: f32,
    };
};

const Paddle = struct {
    box: Box,
    src_rect: *const c.SDL_FRect,
};

const Ball = struct {
    box: Box,
    vel_x: f32,
    vel_y: f32,
    launched: bool,
    src_rect: *const c.SDL_FRect,

    fn getPaddleBounceAngle(ball_: Ball, paddle_: Paddle) f32 {
        const min_x = paddle_.box.x - ball_.box.w;
        const max_x = paddle_.box.x + paddle_.box.w;
        const min_angle = std.math.degreesToRadians(195);
        const max_angle = std.math.degreesToRadians(345);
        const angle = ((ball_.box.x - min_x) / (max_x - min_x)) * (max_angle - min_angle) + min_angle;
        return std.math.clamp(angle, min_angle, max_angle);
    }
};

const Brick = struct {
    box: Box,
    src_rect: *const c.SDL_FRect,
};

fn renderObject(renderer_: *c.SDL_Renderer, texture: *c.SDL_Texture, src: *const c.SDL_FRect, dst: Box) !void {
    try errify(c.SDL_RenderTexture(renderer_, texture, src, &.{
        .x = dst.x,
        .y = dst.y,
        .w = dst.w,
        .h = dst.h,
    }));
}

const PhysicalControllerState = struct {
    k_left: bool = false,
    k_right: bool = false,
    k_lshift: bool = false,
    k_space: bool = false,
    k_r: bool = false,
    k_escape: bool = false,

    m_left: bool = false,
    m_xrel: f32 = 0,

    g_left: bool = false,
    g_right: bool = false,
    g_left_shoulder: bool = false,
    g_right_shoulder: bool = false,
    g_south: bool = false,
    g_east: bool = false,
    g_back: bool = false,
    g_start: bool = false,
    g_leftx: i16 = 0,
    g_left_trigger: i16 = 0,
    g_right_trigger: i16 = 0,
};

const VirtualControllerState = struct {
    move_paddle_left: bool = false,
    move_paddle_right: bool = false,
    slow_paddle_movement: bool = false,
    launch_ball: bool = false,
    reset_game: bool = false,

    lock_mouse: bool = false,
    move_paddle_exact: f32 = 0,
};

/// Facilitates updating the game logic at a fixed rate.
/// Inspired <https://github.com/TylerGlaiel/FrameTimingControl> and the linked article.
const Timekeeper = struct {
    const updates_per_s = 60;
    const max_accumulated_updates = 8;
    const snap_frame_rates = .{ updates_per_s, 30, 120, 144 };
    const ticks_per_tock = 720; // Least common multiple of 'snap_frame_rates'
    const snap_tolerance_us = 200;
    const us_per_s = 1_000_000;

    tocks_per_s: u64,
    accumulated_ticks: u64 = 0,
    previous_timestamp: ?u64 = null,

    fn consume(timekeeper_: *Timekeeper) bool {
        const ticks_per_s: u64 = timekeeper_.tocks_per_s * ticks_per_tock;
        const ticks_per_update: u64 = @divExact(ticks_per_s, updates_per_s);
        if (timekeeper_.accumulated_ticks >= ticks_per_update) {
            timekeeper_.accumulated_ticks -= ticks_per_update;
            return true;
        } else {
            return false;
        }
    }

    fn produce(timekeeper_: *Timekeeper, current_timestamp: u64) void {
        if (timekeeper_.previous_timestamp) |previous_timestamp| {
            const ticks_per_s: u64 = timekeeper_.tocks_per_s * ticks_per_tock;
            const elapsed_ticks: u64 = (current_timestamp -% previous_timestamp) *| ticks_per_tock;
            const snapped_elapsed_ticks: u64 = inline for (snap_frame_rates) |snap_frame_rate| {
                const target_ticks: u64 = @divExact(ticks_per_s, snap_frame_rate);
                const abs_diff = @max(elapsed_ticks, target_ticks) - @min(elapsed_ticks, target_ticks);
                if (abs_diff *| us_per_s <= snap_tolerance_us *| ticks_per_s) {
                    break target_ticks;
                }
            } else elapsed_ticks;
            const ticks_per_update: u64 = @divExact(ticks_per_s, updates_per_s);
            const max_accumulated_ticks: u64 = max_accumulated_updates * ticks_per_update;
            timekeeper_.accumulated_ticks = @min(timekeeper_.accumulated_ticks +| snapped_elapsed_ticks, max_accumulated_ticks);
        }
        timekeeper_.previous_timestamp = current_timestamp;
    }
};

const best_score_storage_org = "zig-examples";
const best_score_storage_app = "breakout";
const best_score_storage_path = "best_score";

fn loadBestScore() !void {
    const storage: *c.SDL_Storage = try errify(c.SDL_OpenUserStorage(best_score_storage_org, best_score_storage_app, 0));
    defer errify(c.SDL_CloseStorage(storage)) catch {};

    std.debug.assert(c.SDL_StorageReady(storage));

    const default_score = 100 * Timekeeper.updates_per_s;

    var best_score_le: u32 = undefined;
    errify(c.SDL_ReadStorageFile(storage, best_score_storage_path, &best_score_le, @sizeOf(u32))) catch {
        app_log.debug("failed to load best score: SDL error: {s}", .{c.SDL_GetError()});
        best_score = default_score;
        return;
    };
    best_score = @min(std.mem.littleToNative(u32, best_score_le), default_score);

    app_log.debug("loaded best score: {}", .{best_score});
}

fn saveBestScore() !void {
    const storage: *c.SDL_Storage = try errify(c.SDL_OpenUserStorage(best_score_storage_org, best_score_storage_app, 0));
    defer errify(c.SDL_CloseStorage(storage)) catch {};

    std.debug.assert(c.SDL_StorageReady(storage));

    const best_score_le = std.mem.nativeToLittle(u32, best_score);
    try errify(c.SDL_WriteStorageFile(storage, best_score_storage_path, &best_score_le, @sizeOf(u32)));

    app_log.debug("saved best score: {}", .{best_score});
}

const fmtSdlDrivers = if (post_writergate) fmtSdlDriversPostWritergate else fmtSdlDriversPreWritergate;

fn fmtSdlDriversPostWritergate(
    current_driver: [*:0]const u8,
    num_drivers: c_int,
    getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,
) std.fmt.Alt(@typeInfo(@TypeOf(formatSdlDriversPostWritergate)).@"fn".params[0].type.?, formatSdlDriversPostWritergate) {
    return .{ .data = .{
        .current_driver = current_driver,
        .num_drivers = num_drivers,
        .getDriver = getDriver,
    } };
}

fn formatSdlDriversPostWritergate(
    context: struct {
        current_driver: [*:0]const u8,
        num_drivers: c_int,
        getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,
    },
    writer: *std.Io.Writer,
) !void {
    var i: c_int = 0;
    while (i < context.num_drivers) : (i += 1) {
        if (i != 0) {
            try writer.writeAll(", ");
        }
        const driver = context.getDriver(i).?;
        try writer.writeAll(std.mem.span(driver));
        if (std.mem.orderZ(u8, context.current_driver, driver) == .eq) {
            try writer.writeAll(" (current)");
        }
    }
}

fn fmtSdlDriversPreWritergate(
    current_driver: [*:0]const u8,
    num_drivers: c_int,
    getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,
) std.fmt.Formatter(formatSdlDriversPreWritergate) {
    return .{ .data = .{
        .current_driver = current_driver,
        .num_drivers = num_drivers,
        .getDriver = getDriver,
    } };
}

fn formatSdlDriversPreWritergate(
    context: struct {
        current_driver: [*:0]const u8,
        num_drivers: c_int,
        getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,
    },
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    var i: c_int = 0;
    while (i < context.num_drivers) : (i += 1) {
        if (i != 0) {
            try writer.writeAll(", ");
        }
        const driver = context.getDriver(i).?;
        try writer.writeAll(std.mem.span(driver));
        if (std.mem.orderZ(u8, context.current_driver, driver) == .eq) {
            try writer.writeAll(" (current)");
        }
    }
}

/// Converts the return value of an SDL function to an error union.
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

//#region SDL main callbacks boilerplate

pub fn main() !u8 {
    app_err.reset();
    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

//#endregion SDL main callbacks boilerplate
