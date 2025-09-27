const std = @import("std");
const rlz = @import("raylib_zig");

// This function is called from the build script to generate a zig file
// containing a list of all the maze files in the resources directory.
fn generateMazeManifest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().createFile("src/maze_manifest.zig", .{.read = false, .truncate = true});
    defer file.close();

    const BUFFER_SIZE: usize = 100 * 1024;
    var writeBuffer: [BUFFER_SIZE]u8 = undefined;
    var writer = file.writer(&writeBuffer);

    _ = try writer.interface.writeAll("pub const maze_files = &[_][]const u8{\n");

    var dir = try std.fs.cwd().openDir("resources", .{});
    defer dir.close();

    var maze_files = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (maze_files.items) |item| {
            allocator.free(item);
        }
        maze_files.deinit();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            if (!std.mem.endsWith(u8, entry.name, ".otf")) {
                try maze_files.append(try allocator.dupe(u8, entry.name));
            }
        }
    }

    // Simple bubble sort to avoid compiler issues with std.mem.sort
    for (maze_files.items, 0..) |_, i| {
        for (maze_files.items, 0..) |_, j| {
            if (j > i) {
                if (std.mem.lessThan(u8, maze_files.items[j], maze_files.items[i])) {
                    const temp = maze_files.items[i];
                    maze_files.items[i] = maze_files.items[j];
                    maze_files.items[j] = temp;
                }
            }
        }
    }

    for (maze_files.items) |maze_file| {
        try writer.interface.print("    \"{s}\",\n", .{maze_file});
    }

    try writer.interface.writeAll("};\n");
    try writer.interface.flush();
}

pub fn build(b: *std.Build) !void {

    // Generate the maze manifest file before building the project.
    generateMazeManifest() catch |err| {
        std.debug.print("Failed to generate maze manifest: {any}\n", .{err});
        return;
    };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // Define modules for both native and Emscripten builds
    const queue_mod = b.createModule(.{
        .root_source_file = b.path("src/queue.zig"),
    });
    const binary_heap_mod = b.createModule(.{
        .root_source_file = b.path("src/binaryheap.zig"),
    });
    const maze_manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/maze_manifest.zig"),
    });

    // Web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        const zemscripten_dep = b.dependency("zemscripten", .{});
        const emsdk_dep = b.dependency("emsdk", .{});

        const zemscripten = zemscripten_dep.module("zemscripten");
        const emsdk = emsdk_dep.module("emsdk");

        const activate_emsdk_step = zemscripten.call(.{
            .name = "activateEmsdkStep",
            .args = .{ b, emsdk.path("root") },
        });

        const wasm_lib = b.addStaticLibrary(.{
            .name = "zigpath",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        wasm_lib.addModule("zemscripten", zemscripten);
        wasm_lib.linkLibC = true;

        wasm_lib.root_module.addImport("raylib", raylib);
        wasm_lib.root_module.addImport("queue", queue_mod);
        wasm_lib.root_module.addImport("BinaryHeap", binary_heap_mod);
        wasm_lib.root_module.addImport("maze_manifest", maze_manifest_mod);

        const emcc_step = zemscripten.call(.{
            .name = "emccStep",
            .args = .{
                b,
                wasm_lib,
                &.{
                    "-s", "ASYNCIFY",
                    "-s", "EXPORTED_FUNCTIONS=['_main']",
                    "-s", "EXPORT_ES6=1",
                    "-s", "MODULARIZE=1",
                },
            },
        });
        emcc_step.dependOn(&activate_emsdk_step.step);

        const install_step = b.addInstallArtifact(emcc_step.out_file, .{
            .dest_dir = .{ .custom = "web" },
        });
        install_step.dependOn(&emcc_step.step);

        const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm_lib.name});
        const emrun_step = zemscripten.call(.{
            .name = "emrunStep",
            .args = .{
                b,
                b.getInstallPath(.{ .custom = "web" }, html_filename),
                &.{},
            },
        });
        emrun_step.dependOn(&install_step.step);

        b.step("build-wasm", "Builds the WebAssembly module").dependOn(&install_step.step);
        b.step("run-wasm", "Builds and opens the web app locally using emrun").dependOn(&emrun_step.step);

        return;
    } else {
        const root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{ .name = "zigpath", .root_module = root_module });

        // Add private modules
        exe.root_module.addImport("queue", queue_mod);
        exe.root_module.addImport("BinaryHeap", binary_heap_mod);
        exe.root_module.addImport("maze_manifest", maze_manifest_mod);

        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run", "Run Project");
        run_step.dependOn(&run_cmd.step);

        b.installArtifact(exe);
    }

    // Add a test step
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_exe = b.addTest(.{
        .root_module = test_module,
    });

    // Add necessary modules to the test executable
    test_exe.root_module.addImport("queue", queue_mod);
    test_exe.root_module.addImport("BinaryHeap", binary_heap_mod);
    test_exe.root_module.addImport("raylib", raylib);
    test_exe.root_module.addImport("maze_manifest", maze_manifest_mod);

    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
