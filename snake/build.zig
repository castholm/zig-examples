// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var emscripten_system_include_path: ?std.Build.LazyPath = null;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot) |sysroot| {
                emscripten_system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "include" }) };
            } else {
                std.log.err("'--sysroot' is required when building for Emscripten", .{});
                std.process.exit(1);
            }
        },
        else => {},
    }

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (emscripten_system_include_path) |path| {
        app_mod.addSystemIncludePath(path);
    }

    app_mod.addCSourceFile(.{
        .file = b.path("snake.c"),
        .flags = &.{ "-Wall", "-Werror" },
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .lto = optimize != .Debug,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    const run = b.step("run", "Run the app");

    if (target.result.os.tag == .emscripten) {
        // Build for the Web.

        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "snake",
            .root_module = app_mod,
        });
        app_lib.want_lto = optimize != .Debug;

        const run_emcc = b.addSystemCommand(&.{"emcc"});

        // Pass 'app_lib' and any static libraries it links with as input files.
        // 'app_lib.getCompileDependencies()' will always return 'app_lib' as the first element.
        for (app_lib.getCompileDependencies(false)) |lib| {
            if (lib.isStaticLibrary()) {
                run_emcc.addArtifactArg(lib);
            }
        }

        if (target.result.cpu.arch == .wasm64) {
            run_emcc.addArg("-sMEMORY64");
        }

        run_emcc.addArgs(switch (optimize) {
            .Debug => &.{
                "-O0",
                // Preserve DWARF debug information.
                "-g",
                // Use UBSan (full runtime).
                "-fsanitize=undefined",
            },
            .ReleaseSafe => &.{
                "-O3",
                // Use UBSan (minimal runtime).
                "-fsanitize=undefined",
                "-fsanitize-minimal-runtime",
            },
            .ReleaseFast => &.{
                "-O3",
            },
            .ReleaseSmall => &.{
                "-Oz",
            },
        });

        if (optimize != .Debug) {
            // Perform link time optimization.
            run_emcc.addArg("-flto");
            // Minify JavaScript code.
            run_emcc.addArgs(&.{ "--closure", "1" });
        }

        run_emcc.addArg("-o");
        const app_html = run_emcc.addOutputFileArg("snake.html");

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", "snake.html" }));
        if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(b.getInstallStep());

        run.dependOn(&run_emrun.step);
    } else {
        // Build for desktop.

        const app_exe = b.addExecutable(.{
            .name = "snake",
            .root_module = app_mod,
        });
        app_exe.want_lto = optimize != .Debug;

        b.installArtifact(app_exe);

        const run_app = b.addRunArtifact(app_exe);
        if (b.args) |args| run_app.addArgs(args);
        run_app.step.dependOn(b.getInstallStep());

        run.dependOn(&run_app.step);
    }
}
