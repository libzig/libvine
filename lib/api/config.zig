const linux = @import("../linux/linux.zig");
const types = @import("../core/types.zig");

pub const IdentitySource = union(enum) {
    generated,
    inline_seed: [32]u8,
};

pub const BootstrapPeer = struct {
    peer_id: types.PeerId,
    address: []const u8,
};

pub const SeedRecord = struct {
    peer_id: types.PeerId,
    published_prefix: types.VinePrefix,
};

pub const PolicyToggles = struct {
    allow_relay: bool = true,
    allow_signaling_upgrade: bool = true,
    strict_allowlist: bool = true,
};

pub const NodeConfig = struct {
    identity: IdentitySource = .generated,
    local_peer_id: ?types.PeerId = null,
    network_id: types.NetworkId,
    tun: linux.tun.TunConfig,
    allowlist: []const types.PeerId = &.{},
    bootstrap_peers: []const BootstrapPeer = &.{},
    seed_records: []const SeedRecord = &.{},
    policy: PolicyToggles = .{},
};

test "config surface exports stable defaults" {
    const config = NodeConfig{
        .network_id = try types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '0', 0 } ++ ([_]u8{0} ** 12),
            .local_address = types.VineAddress.init(.{ 10, 42, 0, 1 }),
            .prefix_len = 24,
        },
    };

    try @import("std").testing.expectEqual(@as(usize, 0), config.allowlist.len);
    try @import("std").testing.expect(config.policy.allow_relay);
    try @import("std").testing.expect(config.local_peer_id == null);
}

test "node config captures allowlist bootstrap peers and policy toggles" {
    const peer = types.PeerId.init(.{0x42} ** types.peer_id_len);
    const config = NodeConfig{
        .identity = .{ .inline_seed = [_]u8{7} ** 32 },
        .local_peer_id = peer,
        .network_id = try types.NetworkId.init("prod"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '1', 0 } ++ ([_]u8{0} ** 12),
            .local_address = types.VineAddress.init(.{ 10, 50, 0, 1 }),
            .prefix_len = 24,
            .mtu = 1300,
        },
        .allowlist = &.{peer},
        .bootstrap_peers = &.{.{ .peer_id = peer, .address = "seed://peer-a" }},
        .seed_records = &.{.{ .peer_id = peer, .published_prefix = try types.VinePrefix.parse("10.50.0.0/24") }},
        .policy = .{
            .allow_relay = false,
            .allow_signaling_upgrade = true,
            .strict_allowlist = true,
        },
    };

    try @import("std").testing.expectEqual(@as(usize, 1), config.allowlist.len);
    try @import("std").testing.expect(config.local_peer_id.?.eql(peer));
    try @import("std").testing.expectEqualStrings("seed://peer-a", config.bootstrap_peers[0].address);
    try @import("std").testing.expect(config.seed_records[0].peer_id.eql(peer));
    try @import("std").testing.expect(!config.policy.allow_relay);
}
