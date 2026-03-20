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
    config_path: ?[]const u8 = null,

    pub fn runForeground(self: *Runtime, config_path: []const u8) void {
        self.phase = .starting;
        self.config_path = config_path;
        self.phase = .running;
    }
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

test "daemon runtime enters running phase in foreground mode" {
    var runtime = init(.{
        .pidfile_path = "/run/libvine/vine.pid",
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });

    runtime.runForeground("/etc/libvine/vine.toml");

    try std.testing.expectEqual(DaemonPhase.running, runtime.phase);
    try std.testing.expectEqualStrings("/etc/libvine/vine.toml", runtime.config_path.?);
}
