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
    pid: ?std.process.Child.Id = null,

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

        self.pid = child.id;
        self.phase = .running;
        return child.id;
    }

    pub fn stop(self: *Runtime) void {
        self.phase = .stopping;
        self.phase = .stopped;
        self.pid = null;
    }

    pub fn snapshot(self: *const Runtime) Snapshot {
        return .{
            .phase = self.phase,
            .config_path = self.config_path,
            .pid = self.pid,
        };
    }

    pub fn writeStateFile(self: *const Runtime, allocator: std.mem.Allocator) !void {
        try ensureParentDir(self.paths.state_path);
        const file = try std.fs.createFileAbsolute(self.paths.state_path, .{ .truncate = true, .mode = 0o600 });
        defer file.close();

        const phase_text = @tagName(self.phase);
        const config_path = self.config_path orelse "";
        const pid = self.pid orelse 0;
        const body = try std.fmt.allocPrint(
            allocator,
            "phase={s}\npid={d}\nconfig_path={s}\n",
            .{ phase_text, pid, config_path },
        );
        defer allocator.free(body);
        try file.writeAll(body);
    }

    pub fn writePidFile(self: *const Runtime, allocator: std.mem.Allocator) !void {
        try ensureParentDir(self.paths.pidfile_path);
        const file = try std.fs.createFileAbsolute(self.paths.pidfile_path, .{ .truncate = true, .mode = 0o600 });
        defer file.close();

        const body = try std.fmt.allocPrint(allocator, "{d}\n", .{self.pid orelse 0});
        defer allocator.free(body);
        try file.writeAll(body);
    }

    pub fn removePidFile(self: *const Runtime) !void {
        std.fs.deleteFileAbsolute(self.paths.pidfile_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
};

pub const Snapshot = struct {
    phase: DaemonPhase,
    config_path: ?[]const u8,
    pid: ?std.process.Child.Id,
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

pub fn readStateFile(allocator: std.mem.Allocator, state_path: []const u8) !Snapshot {
    const file = if (std.fs.path.isAbsolute(state_path))
        try std.fs.openFileAbsolute(state_path, .{})
    else
        try std.fs.cwd().openFile(state_path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(data);

    var snapshot = Snapshot{
        .phase = .stopped,
        .config_path = null,
        .pid = null,
    };

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, '=');
        const key = parts.next() orelse continue;
        const value = parts.next() orelse continue;

        if (std.mem.eql(u8, key, "phase")) {
            snapshot.phase = parsePhase(value) orelse return error.InvalidStateFile;
        } else if (std.mem.eql(u8, key, "pid")) {
            const parsed = std.fmt.parseInt(std.process.Child.Id, value, 10) catch return error.InvalidStateFile;
            snapshot.pid = if (parsed == 0) null else parsed;
        } else if (std.mem.eql(u8, key, "config_path")) {
            snapshot.config_path = if (value.len == 0) null else try allocator.dupe(u8, value);
        }
    }

    return snapshot;
}

pub fn deinitSnapshot(allocator: std.mem.Allocator, snapshot: *Snapshot) void {
    if (snapshot.config_path) |path| allocator.free(path);
    snapshot.* = undefined;
}

pub fn readPidFile(allocator: std.mem.Allocator, pidfile_path: []const u8) !std.process.Child.Id {
    const file = try std.fs.openFileAbsolute(pidfile_path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 64);
    defer allocator.free(data);

    return std.fmt.parseInt(std.process.Child.Id, std.mem.trim(u8, data, " \t\r\n"), 10);
}

pub fn requestShutdown(pid: std.process.Child.Id) !void {
    try std.posix.kill(pid, std.posix.SIG.TERM);
}

pub fn shutdownSignal() u8 {
    return std.posix.SIG.TERM;
}

fn parsePhase(value: []const u8) ?DaemonPhase {
    inline for (std.meta.tags(DaemonPhase)) |phase| {
        if (std.mem.eql(u8, value, @tagName(phase))) return phase;
    }
    return null;
}

fn ensureParentDir(path: []const u8) !void {
    const dirname = std.fs.path.dirname(path) orelse return;
    if (dirname.len == 0) return;

    if (std.fs.path.isAbsolute(path)) {
        var root = try std.fs.openDirAbsolute("/", .{});
        defer root.close();
        try root.makePath(dirname[1..]);
    } else {
        try std.fs.cwd().makePath(dirname);
    }
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

test "daemon runtime stops from running state" {
    var runtime = init(.{
        .pidfile_path = "/run/libvine/vine.pid",
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });

    runtime.runForeground("/etc/libvine/vine.toml");
    runtime.stop();

    try std.testing.expectEqual(DaemonPhase.stopped, runtime.phase);
}

test "daemon runtime writes and reads state snapshots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const state_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/state/runtime.state", .{tmp_path});
    defer std.testing.allocator.free(state_path);

    var runtime = init(.{
        .pidfile_path = "/run/libvine/vine.pid",
        .state_path = state_path,
        .log_path = "/var/log/libvine/vine.log",
    });
    runtime.runForeground("/etc/libvine/vine.toml");
    runtime.pid = 4242;
    try runtime.writeStateFile(std.testing.allocator);

    var snapshot = try readStateFile(std.testing.allocator, state_path);
    defer deinitSnapshot(std.testing.allocator, &snapshot);

    try std.testing.expectEqual(DaemonPhase.running, snapshot.phase);
    try std.testing.expectEqual(@as(?std.process.Child.Id, 4242), snapshot.pid);
    try std.testing.expectEqualStrings("/etc/libvine/vine.toml", snapshot.config_path.?);
}

test "daemon runtime writes reads and removes pidfiles" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const pidfile_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/run/vine.pid", .{tmp_path});
    defer std.testing.allocator.free(pidfile_path);

    var runtime = init(.{
        .pidfile_path = pidfile_path,
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });
    runtime.pid = 31337;
    try runtime.writePidFile(std.testing.allocator);

    const pid = try readPidFile(std.testing.allocator, pidfile_path);
    try std.testing.expectEqual(@as(std.process.Child.Id, 31337), pid);

    try runtime.removePidFile();
    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(pidfile_path, .{}));
}

test "daemon runtime uses sigterm for clean shutdown requests" {
    try std.testing.expectEqual(std.posix.SIG.TERM, shutdownSignal());
}
