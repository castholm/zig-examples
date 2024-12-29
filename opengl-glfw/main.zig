// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const gl = @import("gl");
const glfw = @import("glfw");

var gl_procs: gl.ProcTable = undefined;

pub fn main() !void {
    if (!glfw.init(.{})) return error.GlfwInitFailed;
    defer glfw.terminate();

    const window = glfw.Window.create(320, 240, "gl is a art", null, null, .{
        .context_version_major = gl.info.version_major,
        .context_version_minor = gl.info.version_minor,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
    }) orelse return error.InitFailed;
    defer window.destroy();

    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    if (!gl_procs.init(glfw.getProcAddress)) return error.GlInitFailed;

    gl.makeProcTableCurrent(&gl_procs);
    defer gl.makeProcTableCurrent(null);

    main_loop: while (true) {
        glfw.waitEvents();
        if (window.shouldClose()) break :main_loop;

        // This example draws using only scissor boxes and clearing. No actual shaders!
        gl.Disable(gl.SCISSOR_TEST);
        if (gl.extensionSupported(.NV_scissor_exclusive)) {
            gl.Disable(gl.SCISSOR_TEST_EXCLUSIVE_NV);
            gl.ClearColor(1, 0.8, 0.2, 1);
            gl.Clear(gl.COLOR_BUFFER_BIT);
            gl.Enable(gl.SCISSOR_TEST_EXCLUSIVE_NV);
            gl.ScissorExclusiveNV(72, 56, 8, 8);
        }
        gl.ClearColor(1, 1, 1, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT);
        gl.Enable(gl.SCISSOR_TEST);
        const magic: u256 = 0x1ff8200446024f3a8071e321b0edac0a9bfa56aa4bfa26aa13f20802060401f8;
        var i: gl.int = 0;
        while (i < 256) : (i += 1) {
            if (magic >> @intCast(i) & 1 != 0) {
                gl.Scissor(@rem(i, 16) * 8 + 8, @divTrunc(i, 16) * 8 + 8, 8, 8);
                gl.ClearColor(0, 0, 0, 1);
                gl.Clear(gl.COLOR_BUFFER_BIT);
            }
        }

        window.swapBuffers();
    }
}
