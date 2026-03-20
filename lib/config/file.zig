const std = @import("std");
const types = @import("../core/types.zig");

pub const FileConfig = struct {
    pub const NodeSection = struct {
        name: []const u8 = "",
        network_id: []const u8 = "",
        identity_path: []const u8 = "",
    };

    pub const TunSection = struct {
        name: []const u8 = "",
        address: []const u8 = "",
        prefix_len: u8 = 0,
        mtu: u16 = 1400,
    };

    pub const BootstrapPeer = struct {
        peer_id: []const u8 = "",
        address: []const u8 = "",
    };

    pub const AllowedPeer = struct {
        peer_id: []const u8 = "",
        prefix: []const u8 = "",
        relay_capable: bool = false,
    };

    pub const PolicySection = struct {
        strict_allowlist: bool = true,
        allow_relay: bool = true,
        allow_signaling_upgrade: bool = true,
    };

    raw: []const u8,
    node: NodeSection = .{},
    tun: TunSection = .{},
    bootstrap_peers: []const BootstrapPeer = &.{},
    allowed_peers: []const AllowedPeer = &.{},
    policy: PolicySection = .{},
};

pub fn init(raw: []const u8) FileConfig {
    return .{ .raw = raw };
}

test "file config module exists" {
    const cfg = init("network_id = demo");
    try std.testing.expectEqualStrings("network_id = demo", cfg.raw);
}

test "file config schema captures top level sections" {
    const cfg = FileConfig{
        .raw = "",
        .node = .{
            .name = "alpha",
            .network_id = "home-net",
            .identity_path = "/var/lib/libvine/identity",
        },
        .tun = .{
            .name = "vine0",
            .address = "10.42.0.1",
            .prefix_len = 24,
            .mtu = 1400,
        },
        .bootstrap_peers = &.{.{ .peer_id = "peer-a", .address = "udp://198.51.100.10:4100" }},
        .allowed_peers = &.{.{ .peer_id = "peer-b", .prefix = "10.42.1.0/24", .relay_capable = true }},
    };

    try std.testing.expectEqualStrings("alpha", cfg.node.name);
    try std.testing.expectEqual(@as(u8, 24), cfg.tun.prefix_len);
    try std.testing.expectEqual(@as(usize, 1), cfg.bootstrap_peers.len);
    try std.testing.expectEqual(@as(usize, 1), cfg.allowed_peers.len);
    try std.testing.expect(cfg.policy.strict_allowlist);
    _ = types;
}
