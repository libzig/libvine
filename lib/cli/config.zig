const std = @import("std");
const file_config = @import("../config/file.zig");

const Subcommand = enum {
    validate,
};

pub fn run(args: []const []const u8, default_config_path: []const u8) !void {
    if (args.len == 0) return error.InvalidArguments;

    const command = parseSubcommand(args[0]) orelse return error.InvalidArguments;
    switch (command) {
        .validate => try handleValidate(args[1..], default_config_path),
    }
}

fn handleValidate(args: []const []const u8, default_config_path: []const u8) !void {
    const config_path = try parseConfigPath(args, default_config_path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(raw);

    var cfg = try file_config.parse(allocator, raw);
    defer cfg.deinit(allocator);

    std.debug.print(
        "config valid\npath={s}\nnetwork_id={s}\ntun={s}\n",
        .{ config_path, cfg.node.network_id, cfg.tun.name },
    );
}

fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "validate")) return .validate;
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

test "config subcommands parse correctly" {
    try std.testing.expectEqual(Subcommand.validate, parseSubcommand("validate").?);
    try std.testing.expect(parseSubcommand("init") == null);
}

test "config path flag defaults and overrides" {
    try std.testing.expectEqualStrings(
        "/etc/libvine/vine.toml",
        try parseConfigPath(&.{}, "/etc/libvine/vine.toml"),
    );
    try std.testing.expectEqualStrings(
        "/tmp/vine.toml",
        try parseConfigPath(&.{ "--config", "/tmp/vine.toml" }, "/etc/libvine/vine.toml"),
    );
}

test "validate accepts a well formed config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "vine.toml";
    try tmp.dir.writeFile(.{
        .sub_path = path,
        .data =
            \\[node]
            \\name = "alpha"
            \\network_id = "home-net"
            \\identity_path = "/var/lib/libvine/identity"
            \\
            \\[tun]
            \\name = "vine0"
            \\address = "10.42.0.1"
            \\prefix_len = 24
            \\mtu = 1400
            \\
            \\[policy]
            \\strict_allowlist = true
            \\allow_relay = true
            \\allow_signaling_upgrade = true
        ,
    });

    const abs_path = try tmp.dir.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(abs_path);

    try handleValidate(&.{ "-c", abs_path }, "/etc/libvine/vine.toml");
}
