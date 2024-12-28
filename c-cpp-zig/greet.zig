// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub export fn helloFromZig() void {
    std.debug.print("Hello from Zig!\n", .{});
}
