const std = @import("std");
const version = "0.0.1";
pub const default_config_dir = "/etc/libvine";
pub const default_config_path = "/etc/libvine/vine.toml";

const Command = enum {
    identity,
    config,
    daemon,
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
    if (std.mem.eql(u8, arg, "status")) return .status;
    if (std.mem.eql(u8, arg, "diagnostics")) return .diagnostics;
    return null;
}

fn dispatch(command: Command, args: []const []const u8) !void {
    _ = args;
    switch (command) {
        .identity => std.debug.print("vine identity: not implemented yet\n", .{}),
        .config => std.debug.print("vine config: not implemented yet\n", .{}),
        .daemon => std.debug.print("vine daemon: not implemented yet\n", .{}),
        .status => std.debug.print("vine status: not implemented yet\n", .{}),
        .diagnostics => std.debug.print("vine diagnostics: not implemented yet\n", .{}),
    }
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
        \\    status
        \\    diagnostics
        \\
        \\DEFAULT CONFIG:
        \\    {s}
        \\
    , .{default_config_path});
}
