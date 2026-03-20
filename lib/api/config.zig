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

pub const PolicyToggles = struct {
    allow_relay: bool = true,
    allow_signaling_upgrade: bool = true,
};

pub const NodeConfig = struct {
    identity: IdentitySource = .generated,
    network_id: types.NetworkId,
    tun: linux.tun.TunConfig,
    allowlist: []const types.PeerId = &.{},
    bootstrap_peers: []const BootstrapPeer = &.{},
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
}
