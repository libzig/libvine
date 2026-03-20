const std = @import("std");
const file_config = @import("../config/file.zig");
const identity_store = @import("../config/identity_store.zig");

const Subcommand = enum {
    validate,
};

pub const ConfigError = error{
    InvalidArguments,
    InvalidConfigPath,
    InvalidIdentityPath,
    InvalidConfigPermissions,
    InvalidIdentityPermissions,
};

pub fn run(args: []const []const u8, default_config_path: []const u8) !void {
    if (args.len == 0) return ConfigError.InvalidArguments;

    const command = parseSubcommand(args[0]) orelse return ConfigError.InvalidArguments;
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
    try validateFilesystem(config_path, cfg.node.identity_path);

    std.debug.print(
        "config valid\npath={s}\nnetwork_id={s}\ntun={s}\n",
        .{ config_path, cfg.node.network_id, cfg.tun.name },
    );
}

fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "validate")) return .validate;
    return null;
}

pub fn parseConfigPath(args: []const []const u8, default_config_path: []const u8) ![]const u8 {
    var config_path = default_config_path;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) return ConfigError.InvalidArguments;
            config_path = args[i];
            continue;
        }

        return ConfigError.InvalidArguments;
    }

    return config_path;
}

pub fn validateFilesystem(config_path: []const u8, identity_path: []const u8) ConfigError!void {
    try validateConfigPath(config_path);
    try validateIdentityPath(identity_path);
}

fn validateConfigPath(config_path: []const u8) ConfigError!void {
    if (!std.fs.path.isAbsolute(config_path)) return ConfigError.InvalidConfigPath;
    const file = std.fs.openFileAbsolute(config_path, .{}) catch return ConfigError.InvalidConfigPath;
    defer file.close();
    const stat = file.stat() catch return ConfigError.InvalidConfigPath;
    if (stat.kind != .file) return ConfigError.InvalidConfigPath;
    if ((stat.mode & 0o022) != 0) return ConfigError.InvalidConfigPermissions;
}

fn validateIdentityPath(identity_path: []const u8) ConfigError!void {
    if (!std.fs.path.isAbsolute(identity_path)) return ConfigError.InvalidIdentityPath;
    const file = std.fs.openFileAbsolute(identity_path, .{}) catch return ConfigError.InvalidIdentityPath;
    defer file.close();
    const stat = file.stat() catch return ConfigError.InvalidIdentityPath;
    if (stat.kind != .file) return ConfigError.InvalidIdentityPath;
    if ((stat.mode & 0o777) != identity_store.expected_file_mode) return ConfigError.InvalidIdentityPermissions;
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

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);

    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{dir_path});
    defer std.testing.allocator.free(identity_path);
    _ = try identity_store.generateAndWrite(identity_path);

    const config_body = try std.fmt.allocPrint(
        std.testing.allocator,
        \\[node]
        \\name = "alpha"
        \\network_id = "home-net"
        \\identity_path = "{s}"
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
        .{identity_path},
    );
    defer std.testing.allocator.free(config_body);

    const config_file = try tmp.dir.createFile("vine.toml", .{ .truncate = true, .mode = 0o600 });
    defer config_file.close();
    try config_file.writeAll(config_body);

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.toml", .{dir_path});
    defer std.testing.allocator.free(config_path);

    try handleValidate(&.{ "-c", config_path }, "/etc/libvine/vine.toml");
}

test "validate rejects relative config paths before daemon startup" {
    try std.testing.expectError(
        ConfigError.InvalidConfigPath,
        validateConfigPath("vine.toml"),
    );
}

test "validate rejects identity files with broad permissions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);

    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{dir_path});
    defer std.testing.allocator.free(identity_path);
    const file = try tmp.dir.createFile("identity", .{ .truncate = true, .mode = 0o644 });
    defer file.close();
    try file.writeAll("format=placeholder\n");

    try std.testing.expectError(
        ConfigError.InvalidIdentityPermissions,
        validateIdentityPath(identity_path),
    );
}
