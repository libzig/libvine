const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libself_dep = b.dependency("libself", .{
        .target = target,
        .optimize = optimize,
    });
    const libmesh_dep = b.dependency("libmesh", .{
        .target = target,
        .optimize = optimize,
    });
    const libdice_dep = b.dependency("libdice", .{
        .target = target,
        .optimize = optimize,
    });
    const libfast_dep = b.dependency("libfast", .{
        .target = target,
        .optimize = optimize,
    });

    const libvine_module = b.createModule(.{
        .root_source_file = b.path("lib/libvine.zig"),
        .target = target,
        .optimize = optimize,
    });
    libvine_module.addImport("libself", libself_dep.module("libself"));
    libvine_module.addImport("libmesh", libmesh_dep.module("libmesh"));
    libvine_module.addImport("libdice", libdice_dep.module("libdice"));
    libvine_module.addImport("libfast", libfast_dep.module("libfast"));

    const libvine_export = b.addModule("libvine", .{
        .root_source_file = b.path("lib/libvine.zig"),
        .target = target,
        .optimize = optimize,
    });
    libvine_export.addImport("libself", libself_dep.module("libself"));
    libvine_export.addImport("libmesh", libmesh_dep.module("libmesh"));
    libvine_export.addImport("libdice", libdice_dep.module("libdice"));
    libvine_export.addImport("libfast", libfast_dep.module("libfast"));

    const lib = b.addLibrary(.{
        .name = "vine",
        .root_module = libvine_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const vine_cli = b.addExecutable(.{
        .name = "vine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bin/vine.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(vine_cli);

    const vine_step = b.step("vine", "Build the vine binary");
    vine_step.dependOn(&vine_cli.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = libvine_module,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const vine_cli_test_module = b.createModule(.{
        .root_source_file = b.path("bin/vine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const vine_cli_tests = b.addTest(.{
        .root_module = vine_cli_test_module,
    });
    const run_vine_cli_tests = b.addRunArtifact(vine_cli_tests);

    const smoke_test_module = b.createModule(.{
        .root_source_file = b.path("test/smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke_test_module.addImport("libvine", libvine_export);

    const smoke_tests = b.addTest(.{
        .root_module = smoke_test_module,
    });
    const run_smoke_tests = b.addRunArtifact(smoke_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_vine_cli_tests.step);
    test_step.dependOn(&run_smoke_tests.step);

    const examples_step = b.step("examples", "Build libvine examples");

    const static_network_demo = b.addExecutable(.{
        .name = "static_network_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/static_network_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    static_network_demo.root_module.addImport("libvine", libvine_export);
    b.installArtifact(static_network_demo);
    examples_step.dependOn(&static_network_demo.step);

    const two_peer_ping = b.addExecutable(.{
        .name = "two_peer_ping",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/two_peer_ping.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    two_peer_ping.root_module.addImport("libvine", libvine_export);
    b.installArtifact(two_peer_ping);
    examples_step.dependOn(&two_peer_ping.step);

    const relay_fallback_ping = b.addExecutable(.{
        .name = "relay_fallback_ping",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/relay_fallback_ping.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    relay_fallback_ping.root_module.addImport("libvine", libvine_export);
    b.installArtifact(relay_fallback_ping);
    examples_step.dependOn(&relay_fallback_ping.step);

    const multi_node_relay_demo = b.addExecutable(.{
        .name = "multi_node_relay_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/multi_node_relay_demo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    multi_node_relay_demo.root_module.addImport("libvine", libvine_export);
    b.installArtifact(multi_node_relay_demo);
    examples_step.dependOn(&multi_node_relay_demo.step);

}
