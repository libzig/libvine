const std = @import("std");
const config = @import("config.zig");
const core = @import("../core/core.zig");
const integration = @import("../integration/integration.zig");
const linux = @import("../linux/linux.zig");

pub const RuntimeBuffers = struct {
    routes: []core.route_table.RouteEntry,
    sessions: []core.session_table.ActiveSession,
};

pub const BootstrapSource = enum {
    static_peers,
    seed_records,
};

pub const BootstrapResult = struct {
    source: BootstrapSource,
    peer_count: usize,
};

pub const Node = struct {
    config: config.NodeConfig,
    local_peer_id: core.types.PeerId,
    local_membership: ?core.membership.LocalMembership = null,
    route_table: core.route_table.RouteTable,
    session_table: core.session_table.SessionTable,
    mesh: integration.libmesh_adapter.LibmeshAdapter = integration.libmesh_adapter.LibmeshAdapter.init(),
    tun: linux.tun.TunDevice,
    running: bool = false,
    last_bootstrap: ?BootstrapResult = null,
    advertised_local_membership: bool = false,

    pub fn init(node_config: config.NodeConfig, buffers: RuntimeBuffers) !Node {
        var tun = try linux.tun.TunDevice.open();
        tun.applyConfig(node_config.tun);

        const local_peer_id = derivePeerId(node_config.identity);
        return .{
            .config = node_config,
            .local_peer_id = local_peer_id,
            .local_membership = .{
                .network_id = node_config.network_id,
                .peer_id = local_peer_id,
                .prefix = try core.types.VinePrefix.init(node_config.tun.local_address, node_config.tun.prefix_len),
                .epoch = core.types.MembershipEpoch.init(1),
                .attached_at_ms = 0,
            },
            .route_table = core.route_table.RouteTable.init(buffers.routes),
            .session_table = core.session_table.SessionTable.init(buffers.sessions),
            .tun = tun,
        };
    }

    pub fn start(self: *Node) void {
        self.running = true;
        _ = self.advertiseLocalMembership();
    }

    pub fn stop(self: *Node) void {
        self.running = false;
        self.tun.fd = -1;
    }

    pub fn bootstrap(self: *Node) ?BootstrapResult {
        if (self.config.bootstrap_peers.len > 0) {
            const result = BootstrapResult{
                .source = .static_peers,
                .peer_count = self.config.bootstrap_peers.len,
            };
            self.last_bootstrap = result;
            return result;
        }

        if (self.config.seed_records.len > 0) {
            const result = BootstrapResult{
                .source = .seed_records,
                .peer_count = self.config.seed_records.len,
            };
            self.last_bootstrap = result;
            return result;
        }

        self.last_bootstrap = null;
        return null;
    }

    pub fn advertiseLocalMembership(self: *Node) ?core.membership.LocalMembership {
        const local_membership = self.local_membership orelse return null;
        self.advertised_local_membership = true;
        return local_membership;
    }
};

fn derivePeerId(source: config.IdentitySource) core.types.PeerId {
    return switch (source) {
        .generated => core.types.PeerId.init(.{0x11} ** core.types.peer_id_len),
        .inline_seed => |seed| {
            var bytes: [core.types.peer_id_len]u8 = undefined;
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update(&seed);
            hasher.final(&bytes);
            return core.types.PeerId.init(bytes);
        },
    };
}

test "node init wires identity membership tun and state tables" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};

    const node = try Node.init(.{
        .identity = .{ .inline_seed = [_]u8{9} ** 32 },
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '0', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 60, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
    });

    try std.testing.expectEqual(@as(usize, 0), node.route_table.entries.len);
    try std.testing.expectEqual(@as(usize, 0), node.session_table.sessions.len);
    try std.testing.expectEqual(@as(i32, 1), node.tun.fd);
    try std.testing.expect(node.local_membership.?.peer_id.eql(node.local_peer_id));
    try std.testing.expect(node.local_membership.?.prefix.contains(core.types.VineAddress.init(.{ 10, 60, 0, 99 })));
}

test "node start and stop bound runtime ownership" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '2', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 61, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
    });

    try std.testing.expect(!node.running);
    node.start();
    try std.testing.expect(node.running);
    node.stop();
    try std.testing.expect(!node.running);
    try std.testing.expectEqual(@as(i32, -1), node.tun.fd);
}

test "node bootstrap prefers static peers and falls back to seed records" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    const peer = core.types.PeerId.init(.{0x42} ** core.types.peer_id_len);

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '3', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 62, 0, 1 }),
            .prefix_len = 24,
        },
        .bootstrap_peers = &.{.{ .peer_id = peer, .address = "seed://peer-a" }},
        .seed_records = &.{.{ .peer_id = peer, .published_prefix = try core.types.VinePrefix.parse("10.62.0.0/24") }},
    }, .{
        .routes = &routes,
        .sessions = &sessions,
    });

    const static_result = node.bootstrap().?;
    try std.testing.expectEqual(BootstrapSource.static_peers, static_result.source);
    try std.testing.expectEqual(@as(usize, 1), static_result.peer_count);

    var seed_only_node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '4', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 63, 0, 1 }),
            .prefix_len = 24,
        },
        .seed_records = &.{.{ .peer_id = peer, .published_prefix = try core.types.VinePrefix.parse("10.63.0.0/24") }},
    }, .{
        .routes = &routes,
        .sessions = &sessions,
    });

    const seed_result = seed_only_node.bootstrap().?;
    try std.testing.expectEqual(BootstrapSource.seed_records, seed_result.source);
    try std.testing.expectEqual(@as(usize, 1), seed_result.peer_count);
}

test "node start advertises local membership" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '5', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 64, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
    });

    node.start();
    try std.testing.expect(node.advertised_local_membership);
    try std.testing.expect(node.advertiseLocalMembership() != null);
}
