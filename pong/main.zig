const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});
const game = @import("game.zig");

const WINDOW_WIDTH = game.WINDOW_WIDTH;
const WINDOW_HEIGHT = game.WINDOW_HEIGHT;

pub var last_time: u64 = 0;
pub var current_time: u64 = 0;
pub var elapsed_time: f32 = 0;

pub fn createWindownAndRenderer() struct { *c.SDL_Window, *c.SDL_Renderer } {
    c.SDL_SetMainReady();

    _ = c.SDL_SetAppMetadata("Pong", "0.0.0", "sdl-examples.pong");
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);

    const window: *c.SDL_Window, const renderer: *c.SDL_Renderer = create_window_and_renderer: {
        var window: ?*c.SDL_Window = null;
        var renderer: ?*c.SDL_Renderer = null;
        _ = c.SDL_CreateWindowAndRenderer("Pong", WINDOW_WIDTH, WINDOW_HEIGHT, 0, &window, &renderer);
        errdefer comptime unreachable;

        break :create_window_and_renderer .{ window.?, renderer.? };
    };

    return .{ window, renderer };
}

fn render(renderer: ?*c.SDL_Renderer) !void {
    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, c.SDL_ALPHA_OPAQUE);
    _ = c.SDL_RenderClear(renderer);

    try game.draw(renderer);

    _ = c.SDL_RenderPresent(renderer);
}

pub fn main() !void {
    const window: *c.SDL_Window, const renderer: *c.SDL_Renderer = createWindownAndRenderer();
    defer c.SDL_Quit();
    defer c.SDL_DestroyRenderer(renderer);
    defer c.SDL_DestroyWindow(window);

    last_time = c.SDL_GetTicks();
    game.initialize();

    main_loop: while (true) {
        var event: c.SDL_Event = undefined;

        while (c.SDL_PollEvent(&event)) {
            game.handleEvent(event) catch |err| {
                if (err == error.Quit) break :main_loop;
            };
        }

        {
            current_time = c.SDL_GetTicks();
            elapsed_time = @as(f32, @floatFromInt(current_time - last_time)) / 1000;
            game.update();
            last_time = c.SDL_GetTicks();
        }

        try render(renderer);
    }
}
