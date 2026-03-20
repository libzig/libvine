const std = @import("std");
const api = @import("../api/api.zig");
const file_config = @import("../config/file.zig");
const identity_store = @import("../config/identity_store.zig");
const core = @import("../core/core.zig");
const linux = @import("../linux/linux.zig");

pub const RuntimeConfig = struct {
    node_config: api.config.NodeConfig,
    local_membership: core.membership.LocalMembership,
};

pub fn load(allocator: std.mem.Allocator, config_path: []const u8) !RuntimeConfig {
    const file = if (std.fs.path.isAbsolute(config_path))
        try std.fs.openFileAbsolute(config_path, .{})
    else
        try std.fs.cwd().openFile(config_path, .{});
    defer file.close();

    const raw = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(raw);

    var parsed = try file_config.parse(allocator, raw);
    defer parsed.deinit(allocator);

    const stored = try identity_store.readFile(allocator, parsed.node.identity_path);

    return .{
        .node_config = .{
            .identity = .{ .inline_seed = stored.seed },
            .local_peer_id = stored.bound.peer_id,
            .network_id = try core.types.NetworkId.init(parsed.node.network_id),
            .tun = try loadTunConfig(parsed.tun),
            .policy = .{
                .allow_relay = parsed.policy.allow_relay,
                .allow_signaling_upgrade = parsed.policy.allow_signaling_upgrade,
                .strict_allowlist = parsed.policy.strict_allowlist,
            },
        },
        .local_membership = .{
            .network_id = try core.types.NetworkId.init(parsed.node.network_id),
            .peer_id = stored.bound.peer_id,
            .prefix = try core.types.VinePrefix.init(
                try core.types.VineAddress.parse(parsed.tun.address),
                parsed.tun.prefix_len,
            ),
            .epoch = core.types.MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
    };
}

fn loadTunConfig(tun: file_config.FileConfig.TunSection) !linux.tun.TunConfig {
    return .{
        .ifname = try parseIfName(tun.name),
        .local_address = try core.types.VineAddress.parse(tun.address),
        .prefix_len = tun.prefix_len,
        .mtu = tun.mtu,
    };
}

fn parseIfName(name: []const u8) ![16]u8 {
    if (name.len == 0 or name.len >= 16) return error.InvalidConfig;

    var ifname = [_]u8{0} ** 16;
    @memcpy(ifname[0..name.len], name);
    return ifname;
}

test "runtime config module captures a node config translation target" {
    const cfg = RuntimeConfig{
        .node_config = .{
            .network_id = try @import("../core/types.zig").NetworkId.init("devnet"),
            .tun = .{
                .ifname = [_]u8{ 'v', 'n', '0', 0 } ++ ([_]u8{0} ** 12),
                .local_address = @import("../core/types.zig").VineAddress.init(.{ 10, 42, 0, 1 }),
                .prefix_len = 24,
            },
        },
        .local_membership = .{
            .network_id = try @import("../core/types.zig").NetworkId.init("devnet"),
            .peer_id = @import("../core/types.zig").PeerId.init(.{0x42} ** @import("../core/types.zig").peer_id_len),
            .prefix = try @import("../core/types.zig").VinePrefix.parse("10.42.0.0/24"),
            .epoch = @import("../core/types.zig").MembershipEpoch.init(1),
            .attached_at_ms = 0,
        },
    };

    try std.testing.expectEqualStrings("devnet", cfg.node_config.network_id.encode());
}

test "runtime config loads node config from persisted config and identity files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    _ = try identity_store.generateAndWrite(identity_path);

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/vine.toml", .{root});
    defer std.testing.allocator.free(config_path);
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
        \\allow_signaling_upgrade = false
        ,
        .{identity_path},
    );
    defer std.testing.allocator.free(config_body);

    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    const loaded = try load(std.testing.allocator, config_path);
    try std.testing.expectEqualStrings("home-net", loaded.node_config.network_id.encode());
    try std.testing.expect(loaded.node_config.local_peer_id != null);
    try std.testing.expectEqual(@as(u8, 24), loaded.node_config.tun.prefix_len);
    try std.testing.expect(!loaded.node_config.policy.allow_signaling_upgrade);
    try std.testing.expectEqual(@as(u8, 'v'), loaded.node_config.tun.ifname[0]);
    try std.testing.expect(loaded.local_membership.prefix.contains(core.types.VineAddress.init(.{ 10, 42, 0, 99 })));
    try std.testing.expect(loaded.local_membership.peer_id.eql(loaded.node_config.local_peer_id.?));
}
