const std = @import("std");
const version = "0.0.1";

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

    std.debug.print("vine: command '{s}' not implemented yet\n", .{args[1]});
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
    , .{});
}
