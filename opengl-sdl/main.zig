// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const gl = @import("gl");

const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    // For programs that provide their own entry points instead of relying on SDL's main function
    // macro magic, 'SDL_MAIN_HANDLED' should be defined before including 'SDL_main.h'.
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

var gl_procs: gl.ProcTable = undefined;

pub fn main() !void {
    errdefer |err| if (err == error.SdlError) std.log.err("SDL error: {s}", .{c.SDL_GetError()});

    // For programs that provide their own entry points instead of relying on SDL's main function
    // macro magic, 'SDL_SetMainReady' should be called before calling 'SDL_Init'.
    c.SDL_SetMainReady();

    try errify(c.SDL_SetAppMetadata("Triangle!", "0.0.0", "example.zig-examples.opengl-sdl"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMEPAD));
    defer c.SDL_Quit();

    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, gl.info.version_major));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, gl.info.version_minor));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE));
    try errify(c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_FLAGS, c.SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG));

    // Zig 0.14.0-dev bug workaround
    const c_SDL_WINDOW_OPENGL: u64 = 0x0000000000000002;
    const c_SDL_WINDOW_RESIZABLE: u64 = 0x0000000000000020;

    const window: *c.SDL_Window = try errify(c.SDL_CreateWindow("Triangle!", 640, 480, c_SDL_WINDOW_OPENGL | c_SDL_WINDOW_RESIZABLE));
    defer c.SDL_DestroyWindow(window);

    const gl_context = try errify(c.SDL_GL_CreateContext(window));
    defer errify(c.SDL_GL_DestroyContext(gl_context)) catch {};

    try errify(c.SDL_GL_MakeCurrent(window, gl_context));
    defer errify(c.SDL_GL_MakeCurrent(window, null)) catch {};

    if (!gl_procs.init(c.SDL_GL_GetProcAddress)) return error.GlInitFailed;

    gl.makeProcTableCurrent(&gl_procs);
    defer gl.makeProcTableCurrent(null);

    const shader_source_preamble =
        \\#version 410 core
        \\
    ;
    const vertex_shader_source =
        \\in vec4 a_Position;
        \\in vec4 a_Color;
        \\out vec4 v_Color;
        \\
        \\void main() {
        \\    gl_Position = a_Position;
        \\    v_Color = a_Color;
        \\}
        \\
    ;
    const fragment_shader_source =
        \\in vec4 v_Color;
        \\out vec4 f_Color;
        \\
        \\void main() {
        \\    f_Color = v_Color;
        \\}
        \\
    ;

    // To keep things simple, this example doesn't check for shader compilation/linking errors.
    // A more robust program would call 'GetProgram/Shaderiv' to check for errors.
    const program = create_program: {
        const vertex_shader = gl.CreateShader(gl.VERTEX_SHADER);
        defer gl.DeleteShader(vertex_shader);

        gl.ShaderSource(
            vertex_shader,
            2,
            &.{ shader_source_preamble.ptr, vertex_shader_source.ptr },
            &.{ @intCast(shader_source_preamble.len), @intCast(vertex_shader_source.len) },
        );
        gl.CompileShader(vertex_shader);

        const fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER);
        defer gl.DeleteShader(fragment_shader);

        gl.ShaderSource(
            fragment_shader,
            2,
            &.{ shader_source_preamble.ptr, fragment_shader_source.ptr },
            &.{ @intCast(shader_source_preamble.len), @intCast(fragment_shader_source.len) },
        );
        gl.CompileShader(fragment_shader);

        const program = gl.CreateProgram();

        gl.AttachShader(program, vertex_shader);
        gl.AttachShader(program, fragment_shader);
        gl.LinkProgram(program);

        break :create_program program;
    };
    defer gl.DeleteProgram(program);

    gl.UseProgram(program);
    defer gl.UseProgram(0);

    var vao: c_uint = undefined;
    gl.GenVertexArrays(1, @ptrCast(&vao));
    defer gl.DeleteVertexArrays(1, @ptrCast(&vao));

    gl.BindVertexArray(vao);
    defer gl.BindVertexArray(0);

    var vbo: c_uint = undefined;
    gl.GenBuffers(1, @ptrCast(&vbo));
    defer gl.DeleteBuffers(1, @ptrCast(&vbo));

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);

    const Vertex = extern struct { position: [2]f32, color: [3]f32 };
    // zig fmt: off
    const vertices = [_]Vertex{
        .{ .position = .{ -0.866,  0.75 }, .color = .{ 0, 1, 1 } },
        .{ .position = .{  0    , -0.75 }, .color = .{ 1, 1, 0 } },
        .{ .position = .{  0.866,  0.75 }, .color = .{ 1, 0, 1 } },
    };
    // zig fmt: on

    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);

    const position_attrib: c_uint = @intCast(gl.GetAttribLocation(program, "a_Position"));
    gl.EnableVertexAttribArray(position_attrib);
    gl.VertexAttribPointer(
        position_attrib,
        @typeInfo(@TypeOf(@as(Vertex, undefined).position)).array.len,
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(Vertex),
        @offsetOf(Vertex, "position"),
    );

    const color_attrib: c_uint = @intCast(gl.GetAttribLocation(program, "a_Color"));
    gl.EnableVertexAttribArray(color_attrib);
    gl.VertexAttribPointer(
        color_attrib,
        @typeInfo(@TypeOf(@as(Vertex, undefined).color)).array.len,
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(Vertex),
        @offsetOf(Vertex, "color"),
    );

    main_loop: while (true) {
        var event: c.SDL_Event = undefined;
        var timeoutMS: i32 = -1;
        while (c.SDL_WaitEventTimeout(&event, timeoutMS)) : (timeoutMS = 0) {
            if (event.type == c.SDL_EVENT_QUIT) break :main_loop;
        }

        // Update the viewport to reflect any changes to the window's size.
        var width: c_int = undefined;
        var height: c_int = undefined;
        try errify(c.SDL_GetWindowSizeInPixels(window, &width, &height));
        gl.Viewport(0, 0, width, height);

        // Clear the window.
        gl.ClearBufferfv(gl.COLOR, 0, &.{ 1, 1, 1, 1 });

        // Draw the vertices.
        gl.DrawArrays(gl.TRIANGLES, 0, vertices.len);

        // Perform some wizardry that prints a nice little message in the center :)
        gl.Enable(gl.SCISSOR_TEST);
        const magic: u154 = 0x3bb924a43ddc000170220543b8006ef4c68ad77;
        const left = @divTrunc(width - 11 * 8, 2);
        const bottom = @divTrunc((height - 14 * 8) * 2, 3);
        var i: gl.int = 0;
        while (i < 154) : (i += 1) {
            if (magic >> @intCast(i) & 1 != 0) {
                gl.Scissor(left + @rem(i, 11) * 8, bottom + @divTrunc(i, 11) * 8, 8, 8);
                gl.ClearBufferfv(gl.COLOR, 0, &.{ 0, 0, 0, 1 });
            }
        }
        gl.Disable(gl.SCISSOR_TEST);

        try errify(c.SDL_GL_SwapWindow(window));
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
