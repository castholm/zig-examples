// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "snake",
        .root_module = exe_mod,
    });

    exe.addCSourceFiles(.{
        .files = &.{
            "snake.c",
        },
        .flags = &.{
            "-Wall",
            "-Werror",
        },
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    exe_mod.linkLibrary(sdl_lib);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run = b.step("run", "Run the game");
    run.dependOn(&run_exe.step);
}
