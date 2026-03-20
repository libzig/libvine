const std = @import("std");
const daemon_runtime = @import("../daemon/runtime.zig");

const Subcommand = enum {
    run,
};

pub const DaemonCommandPaths = daemon_runtime.RuntimePaths;

pub fn run(args: []const []const u8, default_config_path: []const u8, paths: DaemonCommandPaths) !void {
    if (args.len == 0) return error.InvalidArguments;

    const command = parseSubcommand(args[0]) orelse return error.InvalidArguments;
    switch (command) {
        .run => try handleRun(args[1..], default_config_path, paths),
    }
}

fn handleRun(args: []const []const u8, default_config_path: []const u8, paths: DaemonCommandPaths) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var runtime = daemon_runtime.init(paths);
    runtime.runForeground(config_path);
    std.debug.print("daemon running\nconfig_path={s}\n", .{runtime.config_path.?});
}

fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "run")) return .run;
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
    try std.testing.expect(parseSubcommand("start") == null);
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
