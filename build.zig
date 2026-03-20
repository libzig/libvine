const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libvine_module = b.createModule(.{
        .root_source_file = b.path("lib/libvine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const libvine_export = b.addModule("libvine", .{
        .root_source_file = b.path("lib/libvine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "vine",
        .root_module = libvine_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = libvine_module,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const examples_step = b.step("examples", "Build libvine examples");

    _ = libvine_export;
    _ = examples_step;
}
