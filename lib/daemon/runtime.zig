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

    pub fn startBackground(self: *Runtime, allocator: std.mem.Allocator, exe_path: []const u8, config_path: []const u8) !std.process.Child.Id {
        self.phase = .starting;
        self.config_path = config_path;

        const argv = try buildBackgroundArgv(allocator, exe_path, config_path);
        defer allocator.free(argv);

        var child = std.process.Child.init(argv, allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();

        self.phase = .running;
        return child.id;
    }
};

pub fn init(paths: RuntimePaths) Runtime {
    return .{ .paths = paths };
}

pub fn buildBackgroundArgv(allocator: std.mem.Allocator, exe_path: []const u8, config_path: []const u8) ![]const []const u8 {
    const argv = try allocator.alloc([]const u8, 5);
    argv[0] = exe_path;
    argv[1] = "daemon";
    argv[2] = "run";
    argv[3] = "-c";
    argv[4] = config_path;
    return argv;
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

test "daemon runtime builds background argv from current executable and config" {
    const argv = try buildBackgroundArgv(std.testing.allocator, "/tmp/vine", "/etc/libvine/vine.toml");
    defer std.testing.allocator.free(argv);

    try std.testing.expectEqual(@as(usize, 5), argv.len);
    try std.testing.expectEqualStrings("/tmp/vine", argv[0]);
    try std.testing.expectEqualStrings("daemon", argv[1]);
    try std.testing.expectEqualStrings("run", argv[2]);
    try std.testing.expectEqualStrings("/etc/libvine/vine.toml", argv[4]);
}
