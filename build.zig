const std = @import("std");
const rlz = @import("raylib_zig");

// This function is called from the build script to generate a zig file
// containing a list of all the maze files in the resources directory.
fn generateMazeManifest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().createFile("src/maze_manifest.zig", .{});
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    const writer = bw.writer();

    try writer.writeAll("pub const maze_files = &[_][]const u8{\n");

    var dir = try std.fs.cwd().openDir("resources", .{});
    defer dir.close();

    var maze_files = std.ArrayList([]const u8).init(allocator);
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
        try writer.print("    \"{s}\",\n", .{maze_file});
    }

    try writer.writeAll("};\n");
    try bw.flush();
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
        const exe_lib = try rlz.emcc.compileForEmscripten(b, "Project", "src/main.zig", target, optimize);

        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib);
        // Add queue and BinaryHeap modules for Emscripten
        exe_lib.root_module.addImport("queue", queue_mod);
        exe_lib.root_module.addImport("BinaryHeap", binary_heap_mod);
        exe_lib.root_module.addImport("maze_manifest", maze_manifest_mod);

        // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
        const link_step = try rlz.emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
        // This lets your program access files like "resources/my-image.png":
        link_step.addArg("--embed-file");
        link_step.addArg("resources/");
        link_step.addArg("-sINITIAL_MEMORY=64MB");
        link_step.addArg("-sALLOW_MEMORY_GROWTH=1");
        
        b.getInstallStep().dependOn(&link_step.step);
        const run_step = try rlz.emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run Project");
        run_option.dependOn(&run_step.step);
        return;
    }

    const exe = b.addExecutable(.{ .name = "zigpath", .root_source_file = b.path("src/main.zig"), .optimize = optimize, .target = target });

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

    // Add a test step
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
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