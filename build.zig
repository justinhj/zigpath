const std = @import("std");
const rlz = @import("raylib_zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    //web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        const exe_lib = try rlz.emcc.compileForEmscripten(b, "Project", "src/main.zig", target, optimize);

        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib);

        // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
        const link_step = try rlz.emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
        //this lets your program access files like "resources/my-image.png":
        link_step.addArg("--embed-file");
        link_step.addArg("resources/");

        b.getInstallStep().dependOn(&link_step.step);
        const run_step = try rlz.emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run Project");
        run_option.dependOn(&run_step.step);
        return;
    }

    const exe = b.addExecutable(.{ .name = "zigpath", .root_source_file = b.path("src/main.zig"), .optimize = optimize, .target = target });

    // Create private modules
    const queue_mod = b.createModule(.{
        .root_source_file = b.path("src/queue.zig"),
    });
    exe.root_module.addImport("queue", queue_mod);

    const binary_heap_mod = b.createModule(.{
        .root_source_file = b.path("src/binaryheap.zig"),
    });
    exe.root_module.addImport("BinaryHeap", binary_heap_mod);

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

    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);
}
