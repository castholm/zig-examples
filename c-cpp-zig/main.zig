// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const c = @cImport({
    @cInclude("greet.h");
});

pub fn main() void {
    std.debug.print("Entered main.zig\n", .{});
    defer std.debug.print("Leaving main.zig\n", .{});

    c.helloFromC();
    c.helloFromCpp();
    c.helloFromZig();
}
