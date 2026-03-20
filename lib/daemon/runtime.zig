const std = @import("std");

pub const DaemonPhase = enum {
    stopped,
    starting,
    running,
    stopping,
};

pub const RuntimePaths = struct {
    pidfile_path: []const u8,
    state_path: []const u8,
    log_path: []const u8,
};

pub const Runtime = struct {
    paths: RuntimePaths,
    phase: DaemonPhase = .stopped,
};

pub fn init(paths: RuntimePaths) Runtime {
    return .{ .paths = paths };
}

test "daemon runtime module captures paths and initial phase" {
    const runtime = init(.{
        .pidfile_path = "/run/libvine/vine.pid",
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });

    try std.testing.expectEqual(DaemonPhase.stopped, runtime.phase);
    try std.testing.expectEqualStrings("/run/libvine/vine.pid", runtime.paths.pidfile_path);
}
