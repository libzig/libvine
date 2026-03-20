const std = @import("std");
const libvine = @import("libvine");
const version = "0.0.1";
pub const default_config_dir = "/etc/libvine";
pub const default_config_path = "/etc/libvine/vine.toml";
pub const default_state_dir = "/var/lib/libvine";
pub const default_identity_path = "/var/lib/libvine/identity";
pub const default_pidfile_path = "/run/libvine/vine.pid";
pub const default_runtime_state_path = "/run/libvine/state.json";
pub const default_log_path = "/var/log/libvine/vine.log";

const Command = enum {
    identity,
    config,
    daemon,
    up,
    down,
    status,
    diagnostics,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1 or isHelp(args[1])) {
        try printHelp();
        return;
    }

    if (isVersion(args[1])) {
        try printVersion();
        return;
    }

    const command = parseCommand(args[1]) orelse {
        std.debug.print("vine: unknown command '{s}'\n", .{args[1]});
        std.debug.print("Run 'vine help' for usage information\n", .{});
        std.process.exit(1);
    };
    try dispatch(command, args[2..]);
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "help") or
        std.mem.eql(u8, arg, "-h") or
        std.mem.eql(u8, arg, "--help");
}

fn isVersion(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "version") or
        std.mem.eql(u8, arg, "-v") or
        std.mem.eql(u8, arg, "--version");
}

fn printVersion() !void {
    std.debug.print("vine version {s}\n", .{version});
}

fn parseCommand(arg: []const u8) ?Command {
    if (std.mem.eql(u8, arg, "identity")) return .identity;
    if (std.mem.eql(u8, arg, "config")) return .config;
    if (std.mem.eql(u8, arg, "daemon")) return .daemon;
    if (std.mem.eql(u8, arg, "up")) return .up;
    if (std.mem.eql(u8, arg, "down")) return .down;
    if (std.mem.eql(u8, arg, "status")) return .status;
    if (std.mem.eql(u8, arg, "diagnostics")) return .diagnostics;
    return null;
}

fn dispatch(command: Command, args: []const []const u8) !void {
    switch (command) {
        .identity => try libvine.cli.identity.run(args, default_identity_path),
        .config => try libvine.cli.config.run(args, default_config_path),
        .daemon => try libvine.cli.daemon.run(args, default_config_path, .{
            .pidfile_path = default_pidfile_path,
            .state_path = default_runtime_state_path,
            .log_path = default_log_path,
        }),
        .up => try libvine.cli.runtime.runUp(args, default_config_path),
        .down => std.debug.print("vine down: not implemented yet\n", .{}),
        .status => std.debug.print("vine status: not implemented yet\n", .{}),
        .diagnostics => std.debug.print("vine diagnostics: not implemented yet\n", .{}),
    }
}

test "help and version flags parse correctly" {
    try std.testing.expect(isHelp("help"));
    try std.testing.expect(isHelp("-h"));
    try std.testing.expect(isHelp("--help"));
    try std.testing.expect(!isHelp("identity"));

    try std.testing.expect(isVersion("version"));
    try std.testing.expect(isVersion("-v"));
    try std.testing.expect(isVersion("--version"));
    try std.testing.expect(!isVersion("status"));
}

test "top level commands parse correctly" {
    try std.testing.expectEqual(Command.identity, parseCommand("identity").?);
    try std.testing.expectEqual(Command.config, parseCommand("config").?);
    try std.testing.expectEqual(Command.daemon, parseCommand("daemon").?);
    try std.testing.expectEqual(Command.up, parseCommand("up").?);
    try std.testing.expectEqual(Command.down, parseCommand("down").?);
    try std.testing.expectEqual(Command.status, parseCommand("status").?);
    try std.testing.expectEqual(Command.diagnostics, parseCommand("diagnostics").?);
    try std.testing.expect(parseCommand("peers") == null);
}

fn printHelp() !void {
    std.debug.print(
        \\vine - libvine VPN CLI
        \\
        \\USAGE:
        \\    vine <command> [options]
        \\
        \\COMMANDS:
        \\    help
        \\    version
        \\    identity
        \\    config
        \\    daemon
        \\    up
        \\    down
        \\    status
        \\    diagnostics
        \\
        \\DEFAULT CONFIG:
        \\    {s}
        \\
        \\DEFAULT IDENTITY:
        \\    {s}
        \\
        \\DEFAULT DAEMON FILES:
        \\    pidfile: {s}
        \\    state:   {s}
        \\    log:     {s}
        \\
    , .{
        default_config_path,
        default_identity_path,
        default_pidfile_path,
        default_runtime_state_path,
        default_log_path,
    });
}
