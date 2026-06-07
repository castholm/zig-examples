// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

const std = @import("std");
const zigglgen = @import("zigglgen");
const translate_c = @import("translate_c");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.os.tag == .emscripten) return buildWeb(b, target, optimize);

    const app_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .emscripten,
    });
    const app_exe = b.addExecutable(.{
        .name = "opengl_hexagon",
        .root_module = app_mod,
    });

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    const translate_c_dep = b.dependency("translate_c", .{});
    const translator: translate_c.Translator = .init(translate_c_dep, .{
        .c_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#include <SDL3/SDL_revision.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translator.linkLibrary(sdl_lib);
    app_mod.addImport("c", translator.mod);

    app_mod.addImport("gl", zigglgen.generateModule(b, .{
        .api = .gl,
        .version = .@"4.1", // The last OpenGL version supported on macOS
        .profile = .core,
    }));

    b.installArtifact(app_exe);

    const run_app = b.addRunArtifact(app_exe);
    run_app.addPassthruArgs();
    run_app.step.dependOn(b.getInstallStep());

    const run = b.step("run", "Run the app");
    run.dependOn(&run_app.step);
}

fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const system_include_path = b.option(
        std.Build.LazyPath,
        "system_include_path",
        "System header search path for cross-compiling",
    ) orelse {
        std.log.err("'-Dsystem_include_path' is required when building SDL for Emscripten", .{});
        std.process.exit(1);
    };
    const lto: ?std.zig.LtoMode = if (optimize != .Debug) .full else null;

    const app_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const app_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "opengl_hexagon",
        .root_module = app_mod,
    });
    app_lib.lto = lto;

    app_mod.addSystemIncludePath(system_include_path);

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .system_include_path = system_include_path,
        .lto = lto,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    const translate_c_dep = b.dependency("translate_c", .{});
    const translator: translate_c.Translator = .init(translate_c_dep, .{
        .c_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#include <SDL3/SDL_revision.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translator.addSystemIncludePath(system_include_path);
    translator.linkLibrary(sdl_lib);
    app_mod.addImport("c", translator.mod);

    app_mod.addImport("gl", zigglgen.generateModule(b, .{
        .api = .gles,
        .version = .@"3.0", // WebGL 2.0
    }));

    const run_emcc = b.addSystemCommand(&.{"emcc"});

    // Pass 'app_lib' and any static libraries or object files it links with as input files.
    // 'app_lib.getCompileDependencies()' will always return 'app_lib' as the first element.
    for (app_lib.getCompileDependencies(false)) |artifact| {
        if (artifact.isStaticLibrary() or artifact.kind == .obj) {
            run_emcc.addArtifactArg(artifact);
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

    run_emcc.addArg("-sFULL_ES3"); // Currently required by zigglgen

    // Patch the default HTML shell.
    run_emcc.addArg("--pre-js");
    run_emcc.addFileArg(b.addWriteFiles().add("pre.js", (
        // Display messages printed to stderr.
        \\Module['printErr'] ??= Module['print'];
        // Disable ANSI escape sequences.
        \\Module['preRun'] = () => ENV['NO_COLOR'] = '1';
    )));

    run_emcc.addArg("-o");
    const app_html = run_emcc.addOutputFileArg("opengl_hexagon.html");

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = app_html.dirname(),
        .install_dir = .{ .custom = "www" },
        .install_subdir = "",
    }).step);
}
