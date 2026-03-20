const std = @import("std");
const api = @import("../api/api.zig");
const file_config = @import("../config/file.zig");
const identity_store = @import("../config/identity_store.zig");
const core = @import("../core/core.zig");
const linux = @import("../linux/linux.zig");

pub const RuntimeConfig = struct {
    node_config: api.config.NodeConfig,
    local_membership: core.membership.LocalMembership,
    admission_policy: core.policy.AdmissionPolicy,
    startup_bootstrap_peers: []const api.config.BootstrapPeer,
    relay_peers: []const core.types.PeerId,
    enrolled_peers: []const @import("enrollment.zig").EnrollmentState.EnrolledPeer,

    pub fn deinit(self: *RuntimeConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.node_config.allowlist);
        allocator.free(self.node_config.seed_records);
        for (self.node_config.bootstrap_peers) |peer| allocator.free(peer.address);
        allocator.free(self.node_config.bootstrap_peers);
        allocator.free(self.relay_peers);
        allocator.free(self.enrolled_peers);
        self.* = undefined;
    }
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
    const allowlist = try loadAllowlist(allocator, parsed.allowed_peers);
    errdefer allocator.free(allowlist);
    const seed_records = try loadSeedRecords(allocator, parsed.allowed_peers);
    errdefer allocator.free(seed_records);
    const bootstrap_peers = try loadBootstrapPeers(allocator, parsed.bootstrap_peers);
    errdefer allocator.free(bootstrap_peers);
    const relay_peers = try loadRelayPeers(allocator, parsed.allowed_peers);
    errdefer allocator.free(relay_peers);
    const enrolled_peers = try loadEnrolledPeers(allocator, parsed.allowed_peers);
    errdefer allocator.free(enrolled_peers);

    return .{
        .node_config = .{
            .identity = .{ .inline_seed = stored.seed },
            .local_peer_id = stored.bound.peer_id,
            .network_id = try core.types.NetworkId.init(parsed.node.network_id),
            .tun = try loadTunConfig(parsed.tun),
            .allowlist = allowlist,
            .bootstrap_peers = bootstrap_peers,
            .seed_records = seed_records,
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
        .admission_policy = .{
            .allowed_peers = allowlist,
        },
        .startup_bootstrap_peers = bootstrap_peers,
        .relay_peers = relay_peers,
        .enrolled_peers = enrolled_peers,
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

fn loadAllowlist(allocator: std.mem.Allocator, allowed_peers: []const file_config.FileConfig.AllowedPeer) ![]core.types.PeerId {
    const peers = try allocator.alloc(core.types.PeerId, allowed_peers.len);
    for (allowed_peers, 0..) |peer, i| {
        peers[i] = try parsePeerId(peer.peer_id);
    }
    return peers;
}

fn loadSeedRecords(allocator: std.mem.Allocator, allowed_peers: []const file_config.FileConfig.AllowedPeer) ![]api.config.SeedRecord {
    const records = try allocator.alloc(api.config.SeedRecord, allowed_peers.len);
    for (allowed_peers, 0..) |peer, i| {
        records[i] = .{
            .peer_id = try parsePeerId(peer.peer_id),
            .published_prefix = try core.types.VinePrefix.parse(peer.prefix),
        };
    }
    return records;
}

fn loadBootstrapPeers(allocator: std.mem.Allocator, bootstrap_peers: []const file_config.FileConfig.BootstrapPeer) ![]api.config.BootstrapPeer {
    try validateBootstrapPeers(bootstrap_peers);
    const peers = try allocator.alloc(api.config.BootstrapPeer, bootstrap_peers.len);
    errdefer {
        for (peers[0..bootstrap_peers.len]) |peer| {
            if (peer.address.len != 0) allocator.free(peer.address);
        }
        allocator.free(peers);
    }

    for (peers) |*peer| peer.* = .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .address = "" };
    for (bootstrap_peers, 0..) |peer, i| {
        peers[i] = .{
            .peer_id = try parsePeerId(peer.peer_id),
            .address = try allocator.dupe(u8, peer.address),
        };
    }
    return peers;
}

fn validateBootstrapPeers(bootstrap_peers: []const file_config.FileConfig.BootstrapPeer) !void {
    for (bootstrap_peers, 0..) |peer, i| {
        if (peer.peer_id.len == 0 or peer.address.len == 0) return error.InvalidConfig;
        if (std.mem.indexOf(u8, peer.address, "://") == null) return error.InvalidConfig;
        for (bootstrap_peers[i + 1 ..]) |other| {
            if (std.mem.eql(u8, peer.peer_id, other.peer_id)) return error.InvalidConfig;
        }
    }
}

fn loadRelayPeers(allocator: std.mem.Allocator, allowed_peers: []const file_config.FileConfig.AllowedPeer) ![]core.types.PeerId {
    var count: usize = 0;
    for (allowed_peers) |peer| {
        if (peer.relay_capable) count += 1;
    }

    const peers = try allocator.alloc(core.types.PeerId, count);
    var index: usize = 0;
    for (allowed_peers) |peer| {
        if (!peer.relay_capable) continue;
        peers[index] = try parsePeerId(peer.peer_id);
        index += 1;
    }
    return peers;
}

fn loadEnrolledPeers(allocator: std.mem.Allocator, allowed_peers: []const file_config.FileConfig.AllowedPeer) ![]@import("enrollment.zig").EnrollmentState.EnrolledPeer {
    const peers = try allocator.alloc(@import("enrollment.zig").EnrollmentState.EnrolledPeer, allowed_peers.len);
    errdefer allocator.free(peers);
    for (allowed_peers, 0..) |peer, i| {
        peers[i] = .{
            .peer_id = try parsePeerId(peer.peer_id),
            .prefix = try core.types.VinePrefix.parse(peer.prefix),
            .relay_capable = peer.relay_capable,
        };
    }
    try validateNoPrefixOverlap(peers);
    return peers;
}

fn validateNoPrefixOverlap(peers: []const @import("enrollment.zig").EnrollmentState.EnrolledPeer) !void {
    const prefix_policy = core.policy.PrefixPolicy{};
    for (peers, 0..) |peer, i| {
        for (peers[i + 1 ..]) |other| {
            const left = core.membership.PeerMembership{
                .peer_id = peer.peer_id,
                .prefix = peer.prefix,
                .epoch = core.types.MembershipEpoch.init(1),
                .announced_at_ms = 0,
            };
            const right = core.membership.PeerMembership{
                .peer_id = other.peer_id,
                .prefix = other.prefix,
                .epoch = core.types.MembershipEpoch.init(1),
                .announced_at_ms = 0,
            };
            if (prefix_policy.conflicts(left, right)) return error.InvalidConfig;
        }
    }
}

fn parsePeerId(text: []const u8) !core.types.PeerId {
    if (text.len != core.types.peer_id_len * 2) return error.InvalidConfig;

    var bytes: [core.types.peer_id_len]u8 = undefined;
    for (0..core.types.peer_id_len) |i| {
        bytes[i] = std.fmt.parseInt(u8, text[i * 2 .. i * 2 + 2], 16) catch return error.InvalidConfig;
    }
    return core.types.PeerId.init(bytes);
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
        .admission_policy = .{
            .allowed_peers = &.{},
        },
        .startup_bootstrap_peers = &.{},
        .relay_peers = &.{},
        .enrolled_peers = &.{},
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
    const stored = try identity_store.generateAndWrite(identity_path);

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
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.10:4100"
        \\
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.1.0/24"
        \\relay_capable = true
        \\
        \\[policy]
        \\strict_allowlist = true
        \\allow_relay = true
        \\allow_signaling_upgrade = false
        ,
        .{ identity_path, stored.bound.peer_id, stored.bound.peer_id },
    );
    defer std.testing.allocator.free(config_body);

    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    var loaded = try load(std.testing.allocator, config_path);
    defer loaded.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("home-net", loaded.node_config.network_id.encode());
    try std.testing.expect(loaded.node_config.local_peer_id != null);
    try std.testing.expectEqual(@as(u8, 24), loaded.node_config.tun.prefix_len);
    try std.testing.expect(!loaded.node_config.policy.allow_signaling_upgrade);
    try std.testing.expectEqual(@as(u8, 'v'), loaded.node_config.tun.ifname[0]);
    try std.testing.expect(loaded.local_membership.prefix.contains(core.types.VineAddress.init(.{ 10, 42, 0, 99 })));
    try std.testing.expect(loaded.local_membership.peer_id.eql(loaded.node_config.local_peer_id.?));
    try std.testing.expectEqual(@as(usize, 1), loaded.node_config.allowlist.len);
    try std.testing.expectEqual(@as(usize, 1), loaded.node_config.bootstrap_peers.len);
    try std.testing.expectEqualStrings("udp://198.51.100.10:4100", loaded.startup_bootstrap_peers[0].address);
    try std.testing.expect(loaded.admission_policy.allows(stored.bound.peer_id));
    try std.testing.expectEqual(@as(usize, 1), loaded.relay_peers.len);
    try std.testing.expect(loaded.relay_peers[0].eql(stored.bound.peer_id));
    try std.testing.expectEqual(@as(usize, 1), loaded.enrolled_peers.len);
    try std.testing.expect(loaded.enrolled_peers[0].prefix.contains(core.types.VineAddress.init(.{ 10, 42, 1, 7 })));
}

test "runtime config translates multiple configured peers into startup state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    _ = try identity_store.generateAndWrite(identity_path);

    const peer_a = core.types.PeerId.init(.{0x41} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x42} ** core.types.peer_id_len);

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
        \\mtu = 1300
        \\
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.10:4100"
        \\
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.11:4100"
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
        \\allow_relay = false
        \\allow_signaling_upgrade = true
        ,
        .{ identity_path, peer_a, peer_b, peer_a, peer_b },
    );
    defer std.testing.allocator.free(config_body);
    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    var loaded = try load(std.testing.allocator, config_path);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), loaded.startup_bootstrap_peers.len);
    try std.testing.expectEqual(@as(usize, 2), loaded.node_config.allowlist.len);
    try std.testing.expectEqual(@as(usize, 1), loaded.relay_peers.len);
    try std.testing.expect(loaded.relay_peers[0].eql(peer_b));
    try std.testing.expectEqual(@as(usize, 2), loaded.enrolled_peers.len);
    try std.testing.expect(loaded.enrolled_peers[1].relay_capable);
    try std.testing.expect(!loaded.node_config.policy.allow_relay);
}

test "runtime config keeps identity and configured prefix as distinct concerns" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    const stored = try identity_store.generateAndWrite(identity_path);

    const config_a_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/a.toml", .{root});
    defer std.testing.allocator.free(config_a_path);
    const config_b_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/b.toml", .{root});
    defer std.testing.allocator.free(config_b_path);

    const config_a = try std.fmt.allocPrint(
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
        ,
        .{identity_path},
    );
    defer std.testing.allocator.free(config_a);
    const config_b = try std.fmt.allocPrint(
        std.testing.allocator,
        \\[node]
        \\name = "alpha"
        \\network_id = "home-net"
        \\identity_path = "{s}"
        \\
        \\[tun]
        \\name = "vine0"
        \\address = "10.99.0.1"
        \\prefix_len = 24
        \\mtu = 1400
        ,
        .{identity_path},
    );
    defer std.testing.allocator.free(config_b);

    try tmp.dir.writeFile(.{ .sub_path = "a.toml", .data = config_a });
    try tmp.dir.writeFile(.{ .sub_path = "b.toml", .data = config_b });

    var loaded_a = try load(std.testing.allocator, config_a_path);
    defer loaded_a.deinit(std.testing.allocator);
    var loaded_b = try load(std.testing.allocator, config_b_path);
    defer loaded_b.deinit(std.testing.allocator);

    try std.testing.expect(loaded_a.node_config.local_peer_id.?.eql(stored.bound.peer_id));
    try std.testing.expect(loaded_b.node_config.local_peer_id.?.eql(stored.bound.peer_id));
    try std.testing.expect(!loaded_a.local_membership.prefix.network.eql(loaded_b.local_membership.prefix.network));
}

test "runtime config rejects bootstrap peers with duplicate identities or empty addresses" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    const stored = try identity_store.generateAndWrite(identity_path);

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
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = "udp://198.51.100.10:4100"
        \\
        \\[[bootstrap_peers]]
        \\peer_id = "{f}"
        \\address = ""
        ,
        .{ identity_path, stored.bound.peer_id, stored.bound.peer_id },
    );
    defer std.testing.allocator.free(config_body);
    try tmp.dir.writeFile(.{ .sub_path = "vine.toml", .data = config_body });

    try std.testing.expectError(error.InvalidConfig, load(std.testing.allocator, config_path));
}

test "runtime config rejects overlapping configured peer prefixes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const identity_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity", .{root});
    defer std.testing.allocator.free(identity_path);
    _ = try identity_store.generateAndWrite(identity_path);

    const peer_a = core.types.PeerId.init(.{0x41} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x42} ** core.types.peer_id_len);

    const config_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/bad.toml", .{root});
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
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.1.0/24"
        \\relay_capable = false
        \\
        \\[[allowed_peers]]
        \\peer_id = "{f}"
        \\prefix = "10.42.1.128/25"
        \\relay_capable = false
        ,
        .{ identity_path, peer_a, peer_b },
    );
    defer std.testing.allocator.free(config_body);
    try tmp.dir.writeFile(.{ .sub_path = "bad.toml", .data = config_body });

    try std.testing.expectError(error.InvalidConfig, load(std.testing.allocator, config_path));
}
