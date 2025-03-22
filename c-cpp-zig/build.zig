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

    const c_flags = .{ "-Wall", "-Werror" };

    const app_mod = b.createModule(.{
        .root_source_file = if (main_language == .zig) b.path("main.zig") else null,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    const app = b.addExecutable(.{
        .name = "greeter",
        .root_module = app_mod,
    });

    // Make sure we can find 'greet.h'.
    app_mod.addIncludePath(b.path("."));

    // Add the file containing the main entry point.
    switch (main_language) {
        .c => app_mod.addCSourceFile(.{
            .file = b.path("main.c"),
            .flags = &c_flags,
        }),
        .cpp => app_mod.addCSourceFile(.{
            .file = b.path("main.cpp"),
            .flags = &c_flags,
        }),
        .zig => {}, // Already handled by 'b.createModule()'
    }

    // Add the greeter implementations.
    app_mod.addCSourceFiles(.{
        .files = &.{ "greet.c", "greet.cpp" },
        .flags = &c_flags,
    });
    // The Zig compilation model only supports compiling one root Zig source file, which when
    // compiling executables is expected to contain the main entry point. If we want to compile
    // 'greet.zig' like we would C code, we need to explicitly compile it into a separate object.
    app_mod.addObject(b.addObject(.{
        .name = "greet",
        .root_source_file = b.path("greet.zig"),
        .target = target,
        .optimize = optimize,
    }));

    b.installArtifact(app);

    const run_app = b.addRunArtifact(app);
    if (b.args) |args| run_app.addArgs(args);
    run_app.step.dependOn(b.getInstallStep());

    const run = b.step("run", "Run the app");
    run.dependOn(&run_app.step);
}
