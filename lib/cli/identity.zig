const std = @import("std");
const libself = @import("libself");
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
        .show => try handleShow(args[1..], default_identity_path),
        .export_public => try handleExportPublic(args[1..], default_identity_path),
        .fingerprint => try handleFingerprint(args[1..], default_identity_path),
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

fn handleShow(args: []const []const u8, default_identity_path: []const u8) !void {
    const identity_path = try parseIdentityPath(args, default_identity_path);

    const stored = try identity_store.readFile(std.heap.page_allocator, identity_path);
    std.debug.print("identity_path={s}\npeer_id={f}\nfingerprint={s}\n", .{
        identity_path,
        stored.bound.peer_id,
        stored.bound.node_id.toHex(),
    });
}

fn handleExportPublic(args: []const []const u8, default_identity_path: []const u8) !void {
    const identity_path = try parseIdentityPath(args, default_identity_path);
    const stored = try identity_store.readFile(std.heap.page_allocator, identity_path);
    const did = try libself.DidKey.fromKeyPair(stored.bound.key_pair).encode(std.heap.page_allocator);
    defer std.heap.page_allocator.free(did);

    std.debug.print("peer_id={f}\ndid={s}\npublic_key={s}\n", .{
        stored.bound.peer_id,
        did,
        std.fmt.bytesToHex(stored.bound.key_pair.public_key, .lower),
    });
}

fn handleFingerprint(args: []const []const u8, default_identity_path: []const u8) !void {
    const identity_path = try parseIdentityPath(args, default_identity_path);
    const stored = try identity_store.readFile(std.heap.page_allocator, identity_path);
    std.debug.print("{s}\n", .{stored.bound.node_id.toHex()});
}

fn parseIdentityPath(args: []const []const u8, default_identity_path: []const u8) ![]const u8 {
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

    return identity_path;
}

test "identity CLI subcommands parse" {
    try std.testing.expectEqual(Subcommand.init, parseSubcommand("init").?);
    try std.testing.expectEqual(Subcommand.show, parseSubcommand("show").?);
    try std.testing.expectEqual(Subcommand.export_public, parseSubcommand("export-public").?);
    try std.testing.expectEqual(Subcommand.fingerprint, parseSubcommand("fingerprint").?);
    try std.testing.expect(parseSubcommand("rotate") == null);
}
