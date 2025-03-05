// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const main_language = b.option(enum {
        c,
        cpp,
        zig,
    }, "main", "Which language's main function to use (default: Zig)") orelse .zig;

    const c_flags = .{
        "-Wall",
        "-Werror",
    };

    const exe_mod = b.createModule(.{
        .root_source_file = if (main_language == .zig) b.path("main.zig") else null,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const exe = b.addExecutable(.{
        .name = "greeter",
        .root_module = exe_mod,
    });

    // Make sure we can find 'greet.h'.
    exe_mod.addIncludePath(b.path("."));

    // Add the file containing the main entry point.
    switch (main_language) {
        .c => exe_mod.addCSourceFiles(.{
            .files = &.{
                "main.c",
            },
            .flags = &c_flags,
        }),
        .cpp => exe_mod.addCSourceFiles(.{
            .files = &.{
                "main.cpp",
            },
            .flags = &c_flags,
        }),
        .zig => {}, // Already handled in 'addExecutable'
    }

    // Add the greet implementations.
    exe_mod.addCSourceFiles(.{
        .files = &.{
            "greet.c",
            "greet.cpp",
        },
        .flags = &c_flags,
    });
    // The Zig compilation model only supports compiling one root Zig source file, which when
    // compiling executables is expected to contain the main entry point. If we want to compile
    // 'greet.zig' like we would C code we need to explicitly compile it as a separate object.
    exe_mod.addObject(b.addObject(.{
        .name = "greet",
        .root_source_file = b.path("greet.zig"),
        .target = target,
        .optimize = optimize,
    }));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    const run = b.step("run", "Run the app");
    run.dependOn(&run_exe.step);
}
