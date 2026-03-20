const std = @import("std");
const cli_config = @import("config.zig");
const file_config = @import("../config/file.zig");
const identity_store = @import("../config/identity_store.zig");
const runtime_config = @import("../runtime/runtime_config.zig");

pub const DoctorError = cli_config.ConfigError || error{
    MissingTunDevice,
};

pub fn run(args: []const []const u8, default_config_path: []const u8) !void {
    const parsed = try parseArgs(args, default_config_path);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw = try std.fs.cwd().readFileAlloc(allocator, parsed.config_path, 1024 * 1024);
    defer allocator.free(raw);

    var cfg = try file_config.parse(allocator, raw);
    defer cfg.deinit(allocator);
    try cli_config.validateFilesystem(parsed.config_path, cfg.node.identity_path);

    _ = try identity_store.readFile(allocator, cfg.node.identity_path);

    var loaded = try runtime_config.load(allocator, parsed.config_path);
    defer loaded.deinit(allocator);

    try validateTunDevice(parsed.tun_device_path);

    std.debug.print(
        "doctor ok\nconfig={s}\nnetwork_id={s}\nidentity={s}\ntun={s}\ntun_device={s}\nbootstrap_peers={d}\nrelay_peers={d}\n",
        .{
            parsed.config_path,
            cfg.node.network_id,
            cfg.node.identity_path,
            cfg.tun.name,
            parsed.tun_device_path,
            loaded.startup_bootstrap_peers.len,
            loaded.relay_peers.len,
        },
    );
}

pub const Args = struct {
    config_path: []const u8,
    tun_device_path: []const u8,
};

fn parseArgs(args: []const []const u8, default_config_path: []const u8) DoctorError!Args {
    var config_path: []const u8 = default_config_path;
    var tun_device_path: []const u8 = "/dev/net/tun";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-c") or std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) return DoctorError.InvalidArguments;
            config_path = args[i];
            continue;
        }
        if (std.mem.eql(u8, args[i], "--tun-device")) {
            i += 1;
            if (i >= args.len) return DoctorError.InvalidArguments;
            tun_device_path = args[i];
            continue;
        }
        return DoctorError.InvalidArguments;
    }

    return .{
        .config_path = config_path,
        .tun_device_path = tun_device_path,
    };
}

fn validateTunDevice(path: []const u8) DoctorError!void {
    const file = if (std.fs.path.isAbsolute(path))
        std.fs.openFileAbsolute(path, .{}) catch return DoctorError.MissingTunDevice
    else
        std.fs.cwd().openFile(path, .{}) catch return DoctorError.MissingTunDevice;
    defer file.close();

    const stat = file.stat() catch return DoctorError.MissingTunDevice;
    if (stat.kind != .file and stat.kind != .character_device) return DoctorError.MissingTunDevice;
}

test "doctor args default and overrides parse correctly" {
    const parsed_default = try parseArgs(&.{}, "/etc/libvine/vine.toml");
    try std.testing.expectEqualStrings("/etc/libvine/vine.toml", parsed_default.config_path);
    try std.testing.expectEqualStrings("/dev/net/tun", parsed_default.tun_device_path);

    const parsed_override = try parseArgs(
        &.{ "-c", "/tmp/vine.toml", "--tun-device", "/tmp/tun" },
        "/etc/libvine/vine.toml",
    );
    try std.testing.expectEqualStrings("/tmp/vine.toml", parsed_override.config_path);
    try std.testing.expectEqualStrings("/tmp/tun", parsed_override.tun_device_path);
}

test "doctor validates a prepared host layout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);

    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/alpha.identity", .{dir_path});
    defer std.testing.allocator.free(identity_path);
    const alpha_identity = try identity_store.generateAndWrite(identity_path);

    const beta_identity = try identity_store.fromSeed([_]u8{0x44} ** 32);
    const relay_identity = try identity_store.fromSeed([_]u8{0x55} ** 32);

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
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.40:4100"
        \\
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.1.0/24"
        \\relay_capable = false
        \\
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.254.0/24"
        \\relay_capable = true
        \\
        \\[policy]
        \\strict_allowlist = true
        \\allow_relay = true
        \\allow_signaling_upgrade = true
        ,
        .{ identity_path, relay_identity.bound.peer_id, beta_identity.bound.peer_id, relay_identity.bound.peer_id },
    );
    defer std.testing.allocator.free(config_body);

    const config_file = try tmp.dir.createFile("vine.toml", .{ .truncate = true, .mode = 0o600 });
    defer config_file.close();
    try config_file.writeAll(config_body);

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.toml", .{dir_path});
    defer std.testing.allocator.free(config_path);

    const tun_file = try tmp.dir.createFile("tun-device", .{ .truncate = true, .mode = 0o600 });
    defer tun_file.close();

    const tun_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/tun-device", .{dir_path});
    defer std.testing.allocator.free(tun_path);

    _ = alpha_identity;
    try run(&.{ "-c", config_path, "--tun-device", tun_path }, "/etc/libvine/vine.toml");
}

test "doctor rejects a missing tun device path" {
    try std.testing.expectError(
        DoctorError.MissingTunDevice,
        validateTunDevice("/definitely/missing/tun"),
    );
}
