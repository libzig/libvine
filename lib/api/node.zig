const std = @import("std");
const config = @import("config.zig");
const core = @import("../core/core.zig");
const integration = @import("../integration/integration.zig");
const linux = @import("../linux/linux.zig");
const enrollment = @import("../runtime/enrollment.zig");

pub const RuntimeBuffers = struct {
    routes: []core.route_table.RouteEntry,
    sessions: []core.session_table.ActiveSession,
    memberships: []core.membership.PeerMembership,
};

pub const BootstrapSource = enum {
    static_peers,
    seed_records,
};

pub const BootstrapResult = struct {
    source: BootstrapSource,
    peer_count: usize,
};

pub const Event = union(enum) {
    log: []const u8,
    diagnostic: []const u8,
    topology_change: core.types.PeerId,
};

pub const EventCallback = *const fn (?*anyopaque, Event) void;

pub const DiagnosticsCounters = struct {
    packets_sent: usize = 0,
    packets_received: usize = 0,
    route_misses: usize = 0,
    session_failures: usize = 0,
    fallback_transitions: usize = 0,
};

pub const SessionTableSnapshot = struct {
    sessions: []const core.session_table.ActiveSession,
};

pub const NodeSnapshot = struct {
    running: bool,
    local_peer_id: core.types.PeerId,
    diagnostics: DiagnosticsCounters,
    session_table: SessionTableSnapshot,
    local_prefix: ?core.types.VinePrefix,
    advertised_prefixes: []const core.membership.PeerMembership,
};

pub const Node = struct {
    config: config.NodeConfig,
    local_peer_id: core.types.PeerId,
    local_membership: ?core.membership.LocalMembership = null,
    remote_memberships: []core.membership.PeerMembership,
    route_table: core.route_table.RouteTable,
    session_table: core.session_table.SessionTable,
    mesh: integration.libmesh_adapter.LibmeshAdapter = integration.libmesh_adapter.LibmeshAdapter.init(),
    tun: linux.tun.TunDevice,
    running: bool = false,
    last_bootstrap: ?BootstrapResult = null,
    advertised_local_membership: bool = false,
    event_callback: ?EventCallback = null,
    event_context: ?*anyopaque = null,
    diagnostics: DiagnosticsCounters = .{},

    pub fn init(node_config: config.NodeConfig, buffers: RuntimeBuffers) !Node {
        var tun = try linux.tun.TunDevice.open();
        tun.applyConfig(node_config.tun);

        const local_peer_id = node_config.local_peer_id orelse derivePeerId(node_config.identity);
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
            .remote_memberships = buffers.memberships,
            .route_table = core.route_table.RouteTable.init(buffers.routes),
            .session_table = core.session_table.SessionTable.init(buffers.sessions),
            .tun = tun,
        };
    }

    pub fn start(self: *Node) void {
        self.running = true;
        _ = self.advertiseLocalMembership();
        self.emit(.{ .log = "node started" });
    }

    pub fn stop(self: *Node) void {
        self.running = false;
        self.tun.fd = -1;
        self.emit(.{ .log = "node stopped" });
    }

    pub fn bootstrap(self: *Node) ?BootstrapResult {
        if (self.config.bootstrap_peers.len > 0) {
            const result = BootstrapResult{
                .source = .static_peers,
                .peer_count = self.config.bootstrap_peers.len,
            };
            self.last_bootstrap = result;
            self.emit(.{ .diagnostic = "bootstrap static peers" });
            return result;
        }

        if (self.config.seed_records.len > 0) {
            const result = BootstrapResult{
                .source = .seed_records,
                .peer_count = self.config.seed_records.len,
            };
            self.last_bootstrap = result;
            self.emit(.{ .diagnostic = "bootstrap seed records" });
            return result;
        }

        self.last_bootstrap = null;
        return null;
    }

    pub fn advertiseLocalMembership(self: *Node) ?core.membership.LocalMembership {
        const local_membership = self.local_membership orelse return null;
        const state = enrollment.EnrollmentState{
            .local_membership = local_membership,
            .admission_policy = .{ .allowed_peers = self.config.allowlist },
            .enrolled_peers = &.{},
        };
        self.advertised_local_membership = true;
        return state.advertiseLocalMembership();
    }

    pub fn setEventCallback(self: *Node, callback: EventCallback, context: ?*anyopaque) void {
        self.event_callback = callback;
        self.event_context = context;
    }

    pub fn refreshRemoteMembership(self: *Node, membership: core.membership.PeerMembership) bool {
        return self.refreshRemoteMembershipForNetwork(self.config.network_id, membership);
    }

    pub fn refreshRemoteMembershipForNetwork(self: *Node, network_id: core.types.NetworkId, membership: core.membership.PeerMembership) bool {
        const local_membership = self.local_membership orelse return false;
        var enrolled_peers_buffer: [core.types.max_prefix_count]enrollment.EnrollmentState.EnrolledPeer = undefined;
        var enrolled_count: usize = 0;
        for (self.config.seed_records) |record| {
            if (enrolled_count >= enrolled_peers_buffer.len) break;
            enrolled_peers_buffer[enrolled_count] = .{
                .peer_id = record.peer_id,
                .prefix = record.published_prefix,
            };
            enrolled_count += 1;
        }
        const state = enrollment.EnrollmentState{
            .local_membership = local_membership,
            .admission_policy = .{ .allowed_peers = self.config.allowlist },
            .enrolled_peers = enrolled_peers_buffer[0..enrolled_count],
        };
        if (!state.refreshRemoteMembership(network_id, self.remote_memberships, membership)) return false;
        const route_entry = state.routeEntryForMembership(membership);
        self.installRouteEntry(route_entry);
        self.emit(.{ .topology_change = membership.peer_id });
        return true;
    }

    pub fn withdrawRemoteMembership(self: *Node, peer_id: core.types.PeerId) bool {
        const local_membership = self.local_membership orelse return false;
        const state = enrollment.EnrollmentState{
            .local_membership = local_membership,
            .admission_policy = .{ .allowed_peers = self.config.allowlist },
            .enrolled_peers = &.{},
        };
        for (self.remote_memberships) |membership| {
            if (!membership.peer_id.eql(peer_id)) continue;
            if (!state.withdrawRemoteMembership(self.remote_memberships, peer_id)) return false;
            self.emit(.{ .topology_change = peer_id });
            return self.route_table.withdraw(membership.prefix);
        }
        return false;
    }

    pub fn sendPacket(self: *Node, packet: []const u8) ?core.types.SessionId {
        const forwarder = core.forwarder.Forwarder{
            .routes = &self.route_table,
            .sessions = &self.session_table,
            .tun = &self.tun,
            .local_peer_id = self.local_peer_id,
        };
        const session = forwarder.forwardOutbound(packet) orelse {
            self.diagnostics.route_misses += 1;
            return null;
        };
        self.diagnostics.packets_sent += 1;
        return session.session_id;
    }

    pub fn receivePacket(self: *Node, source_peer_id: core.types.PeerId, packet: []const u8) bool {
        const forwarder = core.forwarder.Forwarder{
            .routes = &self.route_table,
            .sessions = &self.session_table,
            .tun = &self.tun,
            .local_peer_id = self.local_peer_id,
        };
        if (!forwarder.forwardInbound(source_peer_id, packet)) {
            self.diagnostics.session_failures += 1;
            return false;
        }
        self.diagnostics.packets_received += 1;
        return true;
    }

    pub fn cleanupStaleSession(self: *Node, peer_id: core.types.PeerId) bool {
        var forwarder = core.forwarder.Forwarder{
            .routes = &self.route_table,
            .sessions = &self.session_table,
            .tun = &self.tun,
            .local_peer_id = self.local_peer_id,
        };
        const had_fallback = self.session_table.fallbackToRelay(peer_id) != null;
        if (!forwarder.cleanupStaleSession(peer_id)) {
            self.diagnostics.session_failures += 1;
            return false;
        }
        if (had_fallback) self.diagnostics.fallback_transitions += 1;
        return true;
    }

    pub fn debugSnapshot(self: *const Node) NodeSnapshot {
        return .{
            .running = self.running,
            .local_peer_id = self.local_peer_id,
            .diagnostics = self.diagnostics,
            .session_table = .{
                .sessions = self.session_table.sessions,
            },
            .local_prefix = if (self.local_membership) |membership| membership.prefix else null,
            .advertised_prefixes = self.remote_memberships,
        };
    }

    fn emit(self: *Node, event: Event) void {
        if (self.event_callback) |callback| {
            callback(self.event_context, event);
        }
    }

    fn installRouteEntry(self: *Node, entry: core.route_table.RouteEntry) void {
        self.route_table.upsert(entry) catch {
            for (self.route_table.entries) |*existing| {
                if (existing.epoch.value == 0 and existing.generation == 0 and !existing.tombstone) {
                    existing.* = entry;
                    return;
                }
            }
        };
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
    var memberships = [_]core.membership.PeerMembership{};

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
        .memberships = &memberships,
    });

    try std.testing.expectEqual(@as(usize, 0), node.route_table.entries.len);
    try std.testing.expectEqual(@as(usize, 0), node.session_table.sessions.len);
    try std.testing.expectEqual(@as(i32, 1), node.tun.fd);
    try std.testing.expect(node.local_membership.?.peer_id.eql(node.local_peer_id));
    try std.testing.expect(node.local_membership.?.prefix.contains(core.types.VineAddress.init(.{ 10, 60, 0, 99 })));
}

test "node prefers configured persisted peer id over derived seed hash" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};
    const persisted_peer = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len);

    const node = try Node.init(.{
        .identity = .{ .inline_seed = [_]u8{9} ** 32 },
        .local_peer_id = persisted_peer,
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'p', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 60, 1, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    try std.testing.expect(node.local_peer_id.eql(persisted_peer));
}

test "node start and stop bound runtime ownership" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};

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
        .memberships = &memberships,
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
    var memberships = [_]core.membership.PeerMembership{};
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
        .memberships = &memberships,
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
        .memberships = &memberships,
    });

    const seed_result = seed_only_node.bootstrap().?;
    try std.testing.expectEqual(BootstrapSource.seed_records, seed_result.source);
    try std.testing.expectEqual(@as(usize, 1), seed_result.peer_count);
}

test "node start advertises local membership" {
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{};

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
        .memberships = &memberships,
    });

    node.start();
    try std.testing.expect(node.advertised_local_membership);
    try std.testing.expect(node.advertiseLocalMembership() != null);
}

test "node refreshes and withdraws remote membership state" {
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.65.0.0/24"),
            .peer_id = core.types.PeerId.init(.{0x55} ** core.types.peer_id_len),
            .session_id = core.types.SessionId.init(12),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{
        .{
            .peer_id = core.types.PeerId.init(.{0x55} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.65.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .announced_at_ms = 1,
        },
    };

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .allowlist = &.{core.types.PeerId.init(.{0x55} ** core.types.peer_id_len)},
        .seed_records = &.{.{
            .peer_id = core.types.PeerId.init(.{0x55} ** core.types.peer_id_len),
            .published_prefix = try core.types.VinePrefix.parse("10.65.0.0/24"),
        }},
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '6', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 66, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    try std.testing.expect(node.refreshRemoteMembership(.{
        .peer_id = core.types.PeerId.init(.{0x55} ** core.types.peer_id_len),
        .prefix = try core.types.VinePrefix.parse("10.65.0.0/24"),
        .epoch = core.types.MembershipEpoch.init(2),
        .announced_at_ms = 2,
    }));
    try std.testing.expectEqual(@as(u64, 2), node.remote_memberships[0].epoch.value);
    try std.testing.expect(node.withdrawRemoteMembership(core.types.PeerId.init(.{0x55} ** core.types.peer_id_len)));
    try std.testing.expect(node.route_table.entries[0].tombstone);
}

test "node refresh installs a route entry for accepted membership" {
    var routes = [_]core.route_table.RouteEntry{.{
        .prefix = try core.types.VinePrefix.parse("0.0.0.0/0"),
        .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
        .epoch = core.types.MembershipEpoch.init(0),
        .preference = .relay,
        .generation = 0,
        .tombstone = false,
    }};
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{std.mem.zeroes(core.membership.PeerMembership)};
    const peer = core.types.PeerId.init(.{0x99} ** core.types.peer_id_len);
    const prefix = try core.types.VinePrefix.parse("10.77.0.0/24");

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .allowlist = &.{peer},
        .seed_records = &.{.{ .peer_id = peer, .published_prefix = prefix }},
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'r', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 66, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    try std.testing.expect(node.refreshRemoteMembership(.{
        .peer_id = peer,
        .prefix = prefix,
        .epoch = core.types.MembershipEpoch.init(1),
        .announced_at_ms = 1,
    }));
    try std.testing.expect(node.route_table.entries[0].peer_id.eql(peer));
    try std.testing.expect(node.route_table.entries[0].prefix.contains(core.types.VineAddress.init(.{ 10, 77, 0, 9 })));
}

test "node handles multi peer membership updates with deterministic ownership" {
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("0.0.0.0/0"),
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .epoch = core.types.MembershipEpoch.init(0),
            .preference = .relay,
            .generation = 0,
            .tombstone = false,
        },
        .{
            .prefix = try core.types.VinePrefix.parse("0.0.0.0/0"),
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .epoch = core.types.MembershipEpoch.init(0),
            .preference = .relay,
            .generation = 0,
            .tombstone = false,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{
        std.mem.zeroes(core.membership.PeerMembership),
        std.mem.zeroes(core.membership.PeerMembership),
    };
    const peer_a = core.types.PeerId.init(.{0x31} ** core.types.peer_id_len);
    const peer_b = core.types.PeerId.init(.{0x32} ** core.types.peer_id_len);
    const peer_c = core.types.PeerId.init(.{0x33} ** core.types.peer_id_len);

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .allowlist = &.{ peer_a, peer_b },
        .seed_records = &.{
            .{ .peer_id = peer_a, .published_prefix = try core.types.VinePrefix.parse("10.80.1.0/24") },
            .{ .peer_id = peer_b, .published_prefix = try core.types.VinePrefix.parse("10.80.2.0/24") },
        },
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'm', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 80, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    try std.testing.expect(node.refreshRemoteMembership(.{
        .peer_id = peer_a,
        .prefix = try core.types.VinePrefix.parse("10.80.1.0/24"),
        .epoch = core.types.MembershipEpoch.init(1),
        .announced_at_ms = 1,
    }));
    try std.testing.expect(node.refreshRemoteMembership(.{
        .peer_id = peer_b,
        .prefix = try core.types.VinePrefix.parse("10.80.2.0/24"),
        .epoch = core.types.MembershipEpoch.init(1),
        .announced_at_ms = 2,
    }));
    try std.testing.expect(!node.refreshRemoteMembership(.{
        .peer_id = peer_c,
        .prefix = try core.types.VinePrefix.parse("10.80.3.0/24"),
        .epoch = core.types.MembershipEpoch.init(1),
        .announced_at_ms = 3,
    }));

    try std.testing.expect(node.remote_memberships[0].peer_id.eql(peer_a));
    try std.testing.expect(node.remote_memberships[1].peer_id.eql(peer_b));
    try std.testing.expect(node.route_table.entries[0].peer_id.eql(peer_a));
    try std.testing.expect(node.route_table.entries[1].peer_id.eql(peer_b));
}

test "node emits lifecycle and topology events through callback" {
    const Capture = struct {
        logs: usize = 0,
        diagnostics: usize = 0,
        topology_changes: usize = 0,

        fn handle(context: ?*anyopaque, event: Event) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            switch (event) {
                .log => self.logs += 1,
                .diagnostic => self.diagnostics += 1,
                .topology_change => self.topology_changes += 1,
            }
        }
    };

    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.67.0.0/24"),
            .peer_id = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len),
            .session_id = core.types.SessionId.init(21),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{};
    var memberships = [_]core.membership.PeerMembership{
        .{
            .peer_id = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len),
            .prefix = try core.types.VinePrefix.parse("10.67.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(1),
            .announced_at_ms = 1,
        },
    };
    var capture = Capture{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .allowlist = &.{core.types.PeerId.init(.{0x77} ** core.types.peer_id_len)},
        .seed_records = &.{.{
            .peer_id = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len),
            .published_prefix = try core.types.VinePrefix.parse("10.67.0.0/24"),
        }},
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '7', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 68, 0, 1 }),
            .prefix_len = 24,
        },
        .bootstrap_peers = &.{.{ .peer_id = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len), .address = "seed://peer-b" }},
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    node.setEventCallback(Capture.handle, &capture);

    node.start();
    _ = node.bootstrap();
    _ = node.refreshRemoteMembership(.{
        .peer_id = core.types.PeerId.init(.{0x77} ** core.types.peer_id_len),
        .prefix = try core.types.VinePrefix.parse("10.67.0.0/24"),
        .epoch = core.types.MembershipEpoch.init(2),
        .announced_at_ms = 2,
    });
    _ = node.withdrawRemoteMembership(core.types.PeerId.init(.{0x77} ** core.types.peer_id_len));
    node.stop();

    try std.testing.expectEqual(@as(usize, 2), capture.logs);
    try std.testing.expectEqual(@as(usize, 1), capture.diagnostics);
    try std.testing.expectEqual(@as(usize, 2), capture.topology_changes);
}

test "integration direct path succeeds through libmesh adapter and forwarder" {
    const peer = core.types.PeerId.init(.{0x81} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.110.0.0/24"),
            .peer_id = peer,
            .session_id = core.types.SessionId.init(41),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(41),
            .preference = .direct,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '8', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 109, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    const candidate = integration.libmesh_adapter.CandidatePeer{
        .peer_id = peer,
        .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey(peer.bytes),
    };
    node.mesh = integration.libmesh_adapter.LibmeshAdapter.withReachability(
        &.{candidate},
        &.{.{ .direct = candidate }},
    );

    const handle = node.mesh.openSession(peer).?;
    const packet = @import("../testing/fixtures.zig").packet(.{ 10, 109, 0, 1 }, .{ 10, 110, 0, 7 });
    const forwarder = core.forwarder.Forwarder{
        .routes = &node.route_table,
        .sessions = &node.session_table,
        .tun = &node.tun,
        .local_peer_id = node.local_peer_id,
    };

    try std.testing.expectEqual(@as(u64, 1), handle.session_id.value);
    try std.testing.expectEqual(@as(u64, 41), forwarder.forwardOutbound(&packet).?.session_id.value);
    try std.testing.expect(forwarder.forwardInbound(peer, &packet));
}

test "integration signaling assisted path maps into preferred session" {
    const peer = core.types.PeerId.init(.{0x82} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.111.0.0/24"),
            .peer_id = peer,
            .session_id = core.types.SessionId.init(51),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct_after_signaling,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(51),
            .preference = .direct_after_signaling,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', '9', 0 } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 108, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    const candidate = integration.libmesh_adapter.CandidatePeer{
        .peer_id = peer,
        .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey(peer.bytes),
    };
    node.mesh = integration.libmesh_adapter.LibmeshAdapter.withReachability(
        &.{candidate},
        &.{.{ .signaling_then_direct = candidate }},
    );

    const handle = node.mesh.openSession(peer).?;
    const packet = @import("../testing/fixtures.zig").packet(.{ 10, 108, 0, 1 }, .{ 10, 111, 0, 9 });
    const forwarder = core.forwarder.Forwarder{
        .routes = &node.route_table,
        .sessions = &node.session_table,
        .tun = &node.tun,
        .local_peer_id = node.local_peer_id,
    };

    try std.testing.expectEqual(integration.libmesh_adapter.ReachabilityPlan.Mode.signaling_then_direct, handle.plan.mode());
    try std.testing.expectEqual(@as(u64, 51), forwarder.forwardOutbound(&packet).?.session_id.value);
}

test "integration relay fallback continues carrying packets after direct session loss" {
    const peer = core.types.PeerId.init(.{0x83} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.112.0.0/24"),
            .peer_id = peer,
            .session_id = core.types.SessionId.init(61),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(61),
            .preference = .direct,
        },
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(62),
            .preference = .relay,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'a', '0' } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 107, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });

    const candidate = integration.libmesh_adapter.CandidatePeer{
        .peer_id = peer,
        .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey(peer.bytes),
    };
    node.mesh = integration.libmesh_adapter.LibmeshAdapter.withReachability(
        &.{candidate},
        &.{.{ .relay = candidate }},
    );

    const packet = @import("../testing/fixtures.zig").packet(.{ 10, 107, 0, 1 }, .{ 10, 112, 0, 9 });
    var forwarder = core.forwarder.Forwarder{
        .routes = &node.route_table,
        .sessions = &node.session_table,
        .tun = &node.tun,
        .local_peer_id = node.local_peer_id,
    };

    try std.testing.expectEqual(@as(u64, 61), forwarder.forwardOutbound(&packet).?.session_id.value);
    try std.testing.expect(forwarder.cleanupStaleSession(peer));
    sessions[0] = .{
        .peer_id = peer,
        .session_id = core.types.SessionId.init(62),
        .preference = .relay,
    };
    try std.testing.expectEqual(@as(u64, 62), node.session_table.preferredForPeer(peer).?.session_id.value);
    try std.testing.expect(forwarder.forwardInbound(peer, &packet));
}

test "node diagnostics counters track packet flow misses failures and fallback" {
    const peer = core.types.PeerId.init(.{0x91} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{
        .{
            .prefix = try core.types.VinePrefix.parse("10.113.0.0/24"),
            .peer_id = peer,
            .session_id = core.types.SessionId.init(71),
            .epoch = core.types.MembershipEpoch.init(1),
            .preference = .direct,
        },
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(71),
            .preference = .direct,
        },
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(72),
            .preference = .relay,
        },
    };
    var memberships = [_]core.membership.PeerMembership{};

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'b', '0' } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 106, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    const packet = @import("../testing/fixtures.zig").packet(.{ 10, 106, 0, 1 }, .{ 10, 113, 0, 5 });
    const miss_packet = @import("../testing/fixtures.zig").packet(.{ 10, 106, 0, 1 }, .{ 10, 200, 0, 5 });

    try std.testing.expectEqual(@as(u64, 71), node.sendPacket(&packet).?.value);
    try std.testing.expect(node.receivePacket(peer, &packet));
    try std.testing.expect(node.sendPacket(&miss_packet) == null);
    try std.testing.expect(!node.receivePacket(core.types.PeerId.init(.{0x92} ** core.types.peer_id_len), &packet));
    try std.testing.expect(node.cleanupStaleSession(peer));

    try std.testing.expectEqual(@as(usize, 1), node.diagnostics.packets_sent);
    try std.testing.expectEqual(@as(usize, 1), node.diagnostics.packets_received);
    try std.testing.expectEqual(@as(usize, 1), node.diagnostics.route_misses);
    try std.testing.expectEqual(@as(usize, 1), node.diagnostics.session_failures);
    try std.testing.expectEqual(@as(usize, 1), node.diagnostics.fallback_transitions);
}

test "node debug snapshot exposes node state sessions and advertised prefixes" {
    const peer = core.types.PeerId.init(.{0x93} ** core.types.peer_id_len);
    var routes = [_]core.route_table.RouteEntry{};
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer,
            .session_id = core.types.SessionId.init(81),
            .preference = .relay,
        },
    };
    var memberships = [_]core.membership.PeerMembership{
        .{
            .peer_id = peer,
            .prefix = try core.types.VinePrefix.parse("10.114.0.0/24"),
            .epoch = core.types.MembershipEpoch.init(2),
            .announced_at_ms = 5,
        },
    };

    var node = try Node.init(.{
        .network_id = try core.types.NetworkId.init("devnet"),
        .tun = .{
            .ifname = [_]u8{ 'v', 'n', 'c', '0' } ++ ([_]u8{0} ** 12),
            .local_address = core.types.VineAddress.init(.{ 10, 105, 0, 1 }),
            .prefix_len = 24,
        },
    }, .{
        .routes = &routes,
        .sessions = &sessions,
        .memberships = &memberships,
    });
    node.start();

    const snapshot = node.debugSnapshot();
    try std.testing.expect(snapshot.running);
    try std.testing.expect(snapshot.local_peer_id.eql(node.local_peer_id));
    try std.testing.expectEqual(@as(usize, 1), snapshot.session_table.sessions.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.advertised_prefixes.len);
    try std.testing.expect(snapshot.local_prefix.?.contains(core.types.VineAddress.init(.{ 10, 105, 0, 9 })));
}
