// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.os.tag == .emscripten) return buildWeb(b, target, optimize);

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const app_exe = b.addExecutable(.{
        .name = "snake",
        .root_module = app_mod,
    });

    if (target.result.os.tag == .windows and target.result.abi == .msvc and @import("builtin").zig_version.major <= 15) { // TODO: Remove after 0.16
        // Fix "duplicate symbol" errors by redefining a problematic weak symbol definition in
        // wchar.h which was introduced in Windows SDK version 10.0.26100.0 and which LLVM 20
        // doesn't understand how to handle.
        app_mod.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }

    app_mod.addCSourceFile(.{
        .file = b.path("snake.c"),
        .flags = &.{ "-Wall", "-Werror" },
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    b.installArtifact(app_exe);

    const run_app = b.addRunArtifact(app_exe);
    if (b.args) |args| run_app.addArgs(args);
    run_app.step.dependOn(b.getInstallStep());

    const run = b.step("run", "Run the app");
    run.dependOn(&run_app.step);
}

fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const sysroot = b.sysroot orelse {
        std.log.err("'--sysroot' is required when building for Emscripten", .{});
        std.process.exit(1);
    };
    b.sysroot = null; // 0.16-dev regression workaround
    const sysroot_include_path: std.Build.LazyPath = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "include" }) };
    const lto: ?std.zig.LtoMode = if (optimize != .Debug) .full else null;

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const app_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "snake",
        .root_module = app_mod,
    });
    app_lib.lto = lto;

    app_mod.addSystemIncludePath(sysroot_include_path);

    app_mod.addCSourceFile(.{
        .file = b.path("snake.c"),
        .flags = &.{ "-Wall", "-Werror" },
    });

    b.sysroot = sysroot; // 0.16-dev regression workaround
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .lto = lto,
    });
    b.sysroot = null; // 0.16-dev regression workaround
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

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

    // Patch the default HTML shell.
    run_emcc.addArg("--pre-js");
    run_emcc.addFileArg(b.addWriteFiles().add("pre.js", (
        // Display messages printed to stderr.
        \\Module['printErr'] ??= Module['print'];
    )));

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

    const run = b.step("run", "Run the app");
    run.dependOn(&run_emrun.step);
}
