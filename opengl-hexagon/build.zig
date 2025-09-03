// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const zigglgen = @import("zigglgen");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var system_include_path: ?std.Build.LazyPath = null;
    var lto: ?std.zig.LtoMode = null;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot) |sysroot| {
                system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "include" }) };
            } else {
                std.log.err("'--sysroot' is required when building for Emscripten", .{});
                std.process.exit(1);
            }
            if (optimize != .Debug) {
                lto = .full;
            }
        },
        else => {},
    }

    const app_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .emscripten,
    });

    if (target.result.os.tag == .windows and target.result.abi == .msvc) {
        // Work around a problematic definition in wchar.h in Windows SDK version 10.0.26100.0
        app_mod.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }
    if (system_include_path) |path| {
        app_mod.addSystemIncludePath(path);
    }

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .lto = lto,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    app_mod.addImport("gl", zigglgen.generateBindingsModule(b, if (target.result.os.tag == .emscripten) .{
        .api = .gles,
        .version = .@"3.0", // WebGL 2.0
    } else .{
        .api = .gl,
        .version = .@"4.1", // The last OpenGL version supported on macOS
        .profile = .core,
    }));

    const run = b.step("run", "Run the app");

    if (target.result.os.tag == .emscripten) {
        // Build for the Web.

        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "opengl_hexagon",
            .root_module = app_mod,
        });
        app_lib.lto = lto;

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

        run_emcc.addArgs(&.{
            "-sUSE_OFFSET_CONVERTER", // Required by Zig's '@returnAddress'
            "-sMIN_WEBGL_VERSION=2",
            "-sFULL_ES3", // Currently required by zigglgen
        });

        // Patch the default HTML shell.
        run_emcc.addArg("--pre-js");
        run_emcc.addFileArg(b.addWriteFiles().add("pre.js", (
            // Display messages printed to stderr.
            \\Module['printErr'] ??= Module['print'];
            \\
        )));

        run_emcc.addArg("-o");
        const app_html = run_emcc.addOutputFileArg("opengl_hexagon.html");

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", "opengl_hexagon.html" }));
        if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(b.getInstallStep());

        run.dependOn(&run_emrun.step);
    } else {
        // Build for desktop.

        const app_exe = b.addExecutable(.{
            .name = "opengl_hexagon",
            .root_module = app_mod,
        });
        app_exe.lto = lto;

        b.installArtifact(app_exe);

        const run_app = b.addRunArtifact(app_exe);
        if (b.args) |args| run_app.addArgs(args);
        run_app.step.dependOn(b.getInstallStep());

        run.dependOn(&run_app.step);
    }
}
