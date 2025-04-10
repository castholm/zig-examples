// © 2024 Carl Åstholm
// SPDX-License-Identifier: MIT

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // DW: -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE was needed when compiling for wasm32-emscripten-none but I'm not sure if it is correct to do so.
    const cc_flags = [_][]const u8{
        "-std=c++23",
        "-D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE",
    };

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

    // DW: The example is pure cpp, so the reference to main.zig is removed.
    const app_mod = b.createModule(.{
        // .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .emscripten,
    });

    if (emscripten_system_include_path) |path| {
        app_mod.addSystemIncludePath(path);
    }

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .lto = optimize != .Debug,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");
    app_mod.linkLibrary(sdl_lib);

    const imgui_src = "imgui/src/";
    const imgui_files = [_][]const u8{
        imgui_src ++ "imgui_demo.cpp",
        imgui_src ++ "imgui_draw.cpp",
        imgui_src ++ "imgui_impl_sdl3.cpp",
        imgui_src ++ "imgui_impl_sdlgpu3.cpp",
        imgui_src ++ "imgui_impl_sdlrenderer3.cpp",
        imgui_src ++ "imgui_tables.cpp",
        imgui_src ++ "imgui_widgets.cpp",
        imgui_src ++ "imgui.cpp",
    };

    // DW: structure like this because I wasn't sure when compiling as a library if the library expects main to be defined.
    const app_src = "./";
    const app_files = [_][]const u8{
        app_src ++ "application.cpp",
        app_src ++ "main.cpp",
    };

    const run = b.step("run", "Run the app");

    if (target.result.os.tag == .emscripten) {
        // Build for the Web.

        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "imgui",
            .root_module = app_mod,
        });
        app_lib.root_module.addCSourceFiles(.{ .files = &imgui_files, .flags = &cc_flags });
        app_lib.root_module.addCSourceFiles(.{ .files = &app_files, .flags = &cc_flags });
        app_lib.root_module.addIncludePath(b.path("imgui/include"));
        app_lib.root_module.addIncludePath(b.path("./"));
        app_lib.linkLibCpp();

        app_lib.want_lto = optimize != .Debug;

        const run_emcc = b.addSystemCommand(&.{"emcc"});

        // Pass the full set of linked artifacts as input files.
        for (app_lib.getCompileDependencies(false)) |compile| {
            run_emcc.addArtifactArg(compile);
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

        run_emcc.addArg("-sLEGACY_RUNTIME"); // Currently required by SDL

        // Patch the default HTML shell to also display messages printed to stderr.
        run_emcc.addArg("--pre-js");
        run_emcc.addFileArg(b.addWriteFiles().add("pre.js", (
            \\Module['printErr'] ??= Module['print'];
            \\
        )));

        run_emcc.addArg("-o");
        const app_html = run_emcc.addOutputFileArg("imgui.html");

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", "imgui.html" }));
        if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(b.getInstallStep());

        run.dependOn(&run_emrun.step);
    } else {
        // Build for desktop.

        const app_exe = b.addExecutable(.{
            .name = "imgui",
            .root_module = app_mod,
        });

        app_exe.root_module.addCSourceFiles(.{ .files = &imgui_files, .flags = &cc_flags });
        app_exe.root_module.addCSourceFiles(.{ .files = &app_files, .flags = &cc_flags });
        app_exe.root_module.addIncludePath(b.path("imgui/include"));
        app_exe.root_module.addIncludePath(b.path("./"));
        app_exe.linkLibCpp();
        app_exe.want_lto = optimize != .Debug;

        b.installArtifact(app_exe);

        const run_app = b.addRunArtifact(app_exe);
        if (b.args) |args| run_app.addArgs(args);
        run_app.step.dependOn(b.getInstallStep());

        run.dependOn(&run_app.step);
    }
}
