const std = @import("std");
const daemon_runtime = @import("../daemon/runtime.zig");

const Subcommand = enum {
    run,
    start,
    stop,
    status,
};

pub const DaemonCommandPaths = daemon_runtime.RuntimePaths;

pub fn run(args: []const []const u8, default_config_path: []const u8, paths: DaemonCommandPaths) !void {
    if (args.len == 0) return error.InvalidArguments;

    const command = parseSubcommand(args[0]) orelse return error.InvalidArguments;
    switch (command) {
        .run => try handleRun(args[1..], default_config_path, paths),
        .start => try handleStart(args[1..], default_config_path, paths),
        .stop => try handleStop(args[1..], paths),
        .status => try handleStatus(args[1..], paths),
    }
}

fn handleRun(args: []const []const u8, default_config_path: []const u8, paths: DaemonCommandPaths) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var runtime = daemon_runtime.init(paths);
    runtime.runForeground(config_path);
    std.debug.print("daemon running\nconfig_path={s}\n", .{runtime.config_path.?});
}

fn handleStart(args: []const []const u8, default_config_path: []const u8, paths: DaemonCommandPaths) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config_path = try parseConfigPath(args, default_config_path);
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    var runtime = daemon_runtime.init(paths);
    const pid = try runtime.startBackground(allocator, exe_path, config_path);
    try runtime.writePidFile(allocator);
    std.debug.print("daemon started\npid={d}\n", .{pid});
}

fn handleStop(args: []const []const u8, paths: DaemonCommandPaths) !void {
    if (args.len != 0) return error.InvalidArguments;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pid = daemon_runtime.readPidFile(allocator, paths.pidfile_path) catch {
        std.debug.print("daemon stopped\n", .{});
        return;
    };

    var runtime = daemon_runtime.init(paths);
    runtime.pid = pid;
    runtime.stop();
    try runtime.removePidFile();
    std.debug.print("daemon stopped\npid={d}\n", .{pid});
}

fn handleStatus(args: []const []const u8, paths: DaemonCommandPaths) !void {
    if (args.len != 0) return error.InvalidArguments;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var snapshot = daemon_runtime.readStateFile(allocator, paths.state_path) catch {
        std.debug.print("daemon status\nphase=stopped\n", .{});
        return;
    };
    defer daemon_runtime.deinitSnapshot(allocator, &snapshot);

    const pid = daemon_runtime.readPidFile(allocator, paths.pidfile_path) catch snapshot.pid orelse 0;
    std.debug.print("daemon status\nphase={s}\npid={d}\n", .{ @tagName(snapshot.phase), pid });
}

fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "run")) return .run;
    if (std.mem.eql(u8, arg, "start")) return .start;
    if (std.mem.eql(u8, arg, "stop")) return .stop;
    if (std.mem.eql(u8, arg, "status")) return .status;
    return null;
}

fn parseConfigPath(args: []const []const u8, default_config_path: []const u8) ![]const u8 {
    var config_path = default_config_path;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            config_path = args[i];
            continue;
        }

        return error.InvalidArguments;
    }

    return config_path;
}

test "daemon subcommands parse correctly" {
    try std.testing.expectEqual(Subcommand.run, parseSubcommand("run").?);
    try std.testing.expectEqual(Subcommand.start, parseSubcommand("start").?);
    try std.testing.expectEqual(Subcommand.stop, parseSubcommand("stop").?);
    try std.testing.expectEqual(Subcommand.status, parseSubcommand("status").?);
    try std.testing.expect(parseSubcommand("reload") == null);
}

test "daemon run path defaults and overrides config path" {
    try std.testing.expectEqualStrings(
        "/etc/libvine/vine.toml",
        try parseConfigPath(&.{}, "/etc/libvine/vine.toml"),
    );
    try std.testing.expectEqualStrings(
        "/tmp/vine.toml",
        try parseConfigPath(&.{ "-c", "/tmp/vine.toml" }, "/etc/libvine/vine.toml"),
    );
}

test "daemon start builds background argv with config path" {
    const argv = try daemon_runtime.buildBackgroundArgv(std.testing.allocator, "/tmp/vine", "/tmp/vine.toml");
    defer std.testing.allocator.free(argv);

    try std.testing.expectEqualStrings("/tmp/vine", argv[0]);
    try std.testing.expectEqualStrings("daemon", argv[1]);
    try std.testing.expectEqualStrings("run", argv[2]);
    try std.testing.expectEqualStrings("-c", argv[3]);
}

test "daemon stop rejects unexpected arguments" {
    try std.testing.expectError(
        error.InvalidArguments,
        handleStop(&.{ "--now" }, .{
            .pidfile_path = "/run/libvine/vine.pid",
            .state_path = "/run/libvine/state.json",
            .log_path = "/var/log/libvine/vine.log",
        }),
    );
}

test "daemon status reads persisted runtime state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const state_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/runtime.state", .{dir_path});
    defer std.testing.allocator.free(state_path);

    var runtime = daemon_runtime.init(.{
        .pidfile_path = "/run/libvine/vine.pid",
        .state_path = state_path,
        .log_path = "/var/log/libvine/vine.log",
    });
    runtime.runForeground("/etc/libvine/vine.toml");
    try runtime.writeStateFile(std.testing.allocator);

    var snapshot = try daemon_runtime.readStateFile(std.testing.allocator, state_path);
    defer daemon_runtime.deinitSnapshot(std.testing.allocator, &snapshot);

    try std.testing.expectEqual(daemon_runtime.DaemonPhase.running, snapshot.phase);
}

test "daemon stop removes an existing pidfile" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const pidfile_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.pid", .{dir_path});
    defer std.testing.allocator.free(pidfile_path);

    var runtime = daemon_runtime.init(.{
        .pidfile_path = pidfile_path,
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });
    runtime.pid = 77;
    try runtime.writePidFile(std.testing.allocator);

    try handleStop(&.{}, .{
        .pidfile_path = pidfile_path,
        .state_path = "/run/libvine/state.json",
        .log_path = "/var/log/libvine/vine.log",
    });

    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(pidfile_path, .{}));
}
