const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

pub fn Object(w: comptime_int, h: comptime_int) type {
    return struct {
        position: Position,
        velocity: Velocity,
        shape: c.SDL_FRect,

        pub fn init(pos_x: f32, pos_y: f32, vel_x: f32, vel_y: f32) @This() {
            return @This(){
                .position = .{ .x = pos_x, .y = pos_y },
                .velocity = .{ .x = vel_x, .y = vel_y },
                .shape = c.SDL_FRect{
                    .x = pos_x,
                    .y = pos_y,
                    .w = w,
                    .h = h,
                },
            };
        }

        pub fn setPosition(self: *@This(), x: f32, y: f32) void {
            self.position.x = x;
            self.position.y = y;

            self.shape.x = x;
            self.shape.y = y;
        }


        pub fn updatePositionByTime(self: *@This(), elapsed_time: f32) void {
            const x = self.position.x + self.velocity.x * elapsed_time;
            const y = self.position.y + self.velocity.y * elapsed_time;

            self.setPosition(x, y);
        }

        pub fn draw(self: *@This(), renderer: ?*c.SDL_Renderer) void {
            _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, c.SDL_ALPHA_OPAQUE);
            _ = c.SDL_RenderFillRect(renderer, &self.shape);
        }
    };
}
