const std = @import("std");
const identity_store = @import("../config/identity_store.zig");

pub const Subcommand = enum {
    init,
    show,
    export_public,
    fingerprint,
};

pub fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "init")) return .init;
    if (std.mem.eql(u8, arg, "show")) return .show;
    if (std.mem.eql(u8, arg, "export-public")) return .export_public;
    if (std.mem.eql(u8, arg, "fingerprint")) return .fingerprint;
    return null;
}

pub fn run(args: []const []const u8, default_identity_path: []const u8) !void {
    const subcommand = parseSubcommand(if (args.len > 0) args[0] else "") orelse return error.InvalidIdentityCommand;
    switch (subcommand) {
        .init => try handleInit(args[1..], default_identity_path),
        .show, .export_public, .fingerprint => std.debug.print("vine identity: subcommand not implemented yet\n", .{}),
    }
}

fn handleInit(args: []const []const u8, default_identity_path: []const u8) !void {
    var identity_path = default_identity_path;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--identity-path")) {
            i += 1;
            if (i >= args.len) return error.MissingIdentityPath;
            identity_path = args[i];
        }
    }

    const stored = try identity_store.generateAndWrite(identity_path);
    std.debug.print("initialized identity at {s}\npeer_id={f}\n", .{
        identity_path,
        stored.bound.peer_id,
    });
}

test "identity CLI subcommands parse" {
    try std.testing.expectEqual(Subcommand.init, parseSubcommand("init").?);
    try std.testing.expectEqual(Subcommand.show, parseSubcommand("show").?);
    try std.testing.expectEqual(Subcommand.export_public, parseSubcommand("export-public").?);
    try std.testing.expectEqual(Subcommand.fingerprint, parseSubcommand("fingerprint").?);
    try std.testing.expect(parseSubcommand("rotate") == null);
}
