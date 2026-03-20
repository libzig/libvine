const core = @import("../core/core.zig");
const integration = @import("../integration/integration.zig");

pub const ManagedPeer = struct {
    peer_id: core.types.PeerId,
    relay_capable: bool = false,
};

pub const SessionManager = struct {
    configured_peers: []const ManagedPeer = &.{},
    sessions: core.session_table.SessionTable,
    mesh: integration.libmesh_adapter.LibmeshAdapter = integration.libmesh_adapter.LibmeshAdapter.init(),

    pub fn init(
        configured_peers: []const ManagedPeer,
        session_buffer: []core.session_table.ActiveSession,
    ) SessionManager {
        return .{
            .configured_peers = configured_peers,
            .sessions = core.session_table.SessionTable.init(session_buffer),
        };
    }

    pub fn withMesh(
        configured_peers: []const ManagedPeer,
        session_buffer: []core.session_table.ActiveSession,
        mesh: integration.libmesh_adapter.LibmeshAdapter,
    ) SessionManager {
        var manager = init(configured_peers, session_buffer);
        manager.mesh = mesh;
        return manager;
    }

    pub fn connectConfiguredPeers(self: *SessionManager) usize {
        var connected: usize = 0;
        for (self.configured_peers) |peer| {
            const handle = self.mesh.openSession(peer.peer_id) orelse continue;
            if (self.trackHandle(peer, handle)) {
                connected += 1;
            }
        }
        return connected;
    }

    pub fn directSessionCount(self: SessionManager) usize {
        return countByPreference(self, .direct);
    }

    pub fn signalingSessionCount(self: SessionManager) usize {
        return countByPreference(self, .direct_after_signaling);
    }

    pub fn relaySessionCount(self: SessionManager) usize {
        return countByPreference(self, .relay);
    }

    pub fn preferredSessionForPeer(self: SessionManager, peer_id: core.types.PeerId) ?core.session_table.ActiveSession {
        return self.sessions.preferredForPeer(peer_id);
    }

    pub fn promoteHandle(
        self: *SessionManager,
        peer: ManagedPeer,
        handle: integration.libmesh_adapter.SessionHandle,
    ) bool {
        if (!allowPlan(peer, handle.plan)) return false;
        return self.sessions.promote(.{
            .peer_id = handle.peer_id,
            .session_id = handle.session_id,
            .preference = preferenceForPlan(handle.plan),
        });
    }

    pub fn failPreferredPath(self: *SessionManager, peer_id: core.types.PeerId) ?core.session_table.ActiveSession {
        for (self.sessions.sessions) |*session| {
            if (!session.peer_id.eql(peer_id)) continue;
            if (session.preference == .relay) continue;
            session.* = .{
                .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
                .session_id = .{ .value = 0 },
                .preference = .relay,
            };
        }
        return self.sessions.fallbackToRelay(peer_id);
    }

    pub fn trackHandle(
        self: *SessionManager,
        peer: ManagedPeer,
        handle: integration.libmesh_adapter.SessionHandle,
    ) bool {
        if (!allowPlan(peer, handle.plan)) return false;
        return self.putSession(.{
            .peer_id = handle.peer_id,
            .session_id = handle.session_id,
            .preference = preferenceForPlan(handle.plan),
        });
    }

    fn putSession(self: *SessionManager, session: core.session_table.ActiveSession) bool {
        for (self.sessions.sessions) |*existing| {
            if (existing.peer_id.eql(session.peer_id) and existing.preference == session.preference) {
                existing.* = session;
                return true;
            }
        }
        for (self.sessions.sessions) |*existing| {
            if (existing.session_id.value == 0) {
                existing.* = session;
                return true;
            }
        }
        return false;
    }

    fn preferenceForPlan(plan: integration.libmesh_adapter.ReachabilityPlan) core.route_table.RouteEntry.Preference {
        return switch (plan.mode()) {
            .direct => .direct,
            .signaling_then_direct => .direct_after_signaling,
            .relay => .relay,
        };
    }

    fn allowPlan(peer: ManagedPeer, plan: integration.libmesh_adapter.ReachabilityPlan) bool {
        return switch (plan.mode()) {
            .relay => peer.relay_capable,
            else => true,
        };
    }

    fn countByPreference(self: SessionManager, preference: core.route_table.RouteEntry.Preference) usize {
        var count: usize = 0;
        for (self.sessions.sessions) |session| {
            if (session.session_id.value == 0) continue;
            if (session.preference == preference) count += 1;
        }
        return count;
    }
};

test "session manager captures configured peers and session storage" {
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(.{0x73} ** core.types.peer_id_len),
        .relay_capable = true,
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 73 },
            .preference = .relay,
        },
    };

    const manager = SessionManager.init(&.{peer}, &sessions);

    try @import("std").testing.expectEqual(@as(usize, 1), manager.configured_peers.len);
    try @import("std").testing.expect(manager.configured_peers[0].relay_capable);
    try @import("std").testing.expectEqual(@as(u64, 73), manager.sessions.byPeer(peer.peer_id).?.session_id.value);
}

test "session manager connects configured peers using mesh reachability" {
    const libmesh = @import("libmesh");
    const node_id = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x74} ** 32);
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(node_id.toBytes()),
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .relay,
        },
    };
    var manager = SessionManager.withMesh(
        &.{peer},
        &sessions,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(
            &.{.{
                .peer_id = peer.peer_id,
                .node_id = node_id,
            }},
            &.{.{
                .direct = .{
                    .peer_id = peer.peer_id,
                    .node_id = node_id,
                },
            }},
        ),
    );

    try @import("std").testing.expectEqual(@as(usize, 1), manager.connectConfiguredPeers());
    try @import("std").testing.expectEqual(
        core.route_table.RouteEntry.Preference.direct,
        manager.sessions.preferredForPeer(peer.peer_id).?.preference,
    );
}

test "session manager tracks direct sessions" {
    const libmesh = @import("libmesh");
    const direct_node = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x75} ** 32);
    const direct_peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(direct_node.toBytes()),
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .relay,
        },
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .relay,
        },
    };
    var manager = SessionManager.withMesh(
        &.{direct_peer},
        &sessions,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(
            &.{.{
                .peer_id = direct_peer.peer_id,
                .node_id = direct_node,
            }},
            &.{.{
                .direct = .{
                    .peer_id = direct_peer.peer_id,
                    .node_id = direct_node,
                },
            }},
        ),
    );

    _ = manager.connectConfiguredPeers();
    try @import("std").testing.expectEqual(@as(usize, 1), manager.directSessionCount());
}

test "session manager tracks signaling-assisted sessions" {
    const libmesh = @import("libmesh");
    const signaling_node = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x76} ** 32);
    const signaling_peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(signaling_node.toBytes()),
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .relay,
        },
    };
    var manager = SessionManager.withMesh(
        &.{signaling_peer},
        &sessions,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(
            &.{.{
                .peer_id = signaling_peer.peer_id,
                .node_id = signaling_node,
            }},
            &.{.{
                .signaling_then_direct = .{
                    .peer_id = signaling_peer.peer_id,
                    .node_id = signaling_node,
                },
            }},
        ),
    );

    _ = manager.connectConfiguredPeers();
    try @import("std").testing.expectEqual(@as(usize, 1), manager.signalingSessionCount());
}

test "session manager tracks relay sessions" {
    const libmesh = @import("libmesh");
    const relay_node = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x77} ** 32);
    const relay_peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(relay_node.toBytes()),
        .relay_capable = true,
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .direct,
        },
    };
    var manager = SessionManager.withMesh(
        &.{relay_peer},
        &sessions,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(
            &.{.{
                .peer_id = relay_peer.peer_id,
                .node_id = relay_node,
            }},
            &.{.{
                .relay = .{
                    .peer_id = relay_peer.peer_id,
                    .node_id = relay_node,
                },
            }},
        ),
    );

    _ = manager.connectConfiguredPeers();
    try @import("std").testing.expectEqual(@as(usize, 1), manager.relaySessionCount());
}

test "session manager only accepts relay plans for relay-capable peers" {
    const libmesh = @import("libmesh");
    const relay_node = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x78} ** 32);
    const peer_id = core.types.PeerId.init(relay_node.toBytes());
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .direct,
        },
        .{
            .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len),
            .session_id = .{ .value = 0 },
            .preference = .direct,
        },
    };
    const mesh = integration.libmesh_adapter.LibmeshAdapter.withReachability(
        &.{.{
            .peer_id = peer_id,
            .node_id = relay_node,
        }},
        &.{.{
            .relay = .{
                .peer_id = peer_id,
                .node_id = relay_node,
            },
        }},
    );

    var denied = SessionManager.withMesh(
        &.{.{ .peer_id = peer_id, .relay_capable = false }},
        sessions[0..1],
        mesh,
    );
    try @import("std").testing.expectEqual(@as(usize, 0), denied.connectConfiguredPeers());

    var allowed = SessionManager.withMesh(
        &.{.{ .peer_id = peer_id, .relay_capable = true }},
        sessions[1..2],
        mesh,
    );
    try @import("std").testing.expectEqual(@as(usize, 1), allowed.connectConfiguredPeers());
}

test "session manager prefers direct then signaling then relay at runtime" {
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(.{0x79} ** core.types.peer_id_len),
        .relay_capable = true,
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
    };
    var manager = SessionManager.init(&.{peer}, &sessions);

    try @import("std").testing.expect(manager.trackHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 10 },
        .plan = .{ .relay = .{
            .peer_id = peer.peer_id,
            .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey([_]u8{0x79} ** 32),
        } },
    }));
    try @import("std").testing.expect(manager.trackHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 11 },
        .plan = .{ .signaling_then_direct = .{
            .peer_id = peer.peer_id,
            .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey([_]u8{0x7A} ** 32),
        } },
    }));
    try @import("std").testing.expect(manager.trackHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 12 },
        .plan = .{ .direct = .{
            .peer_id = peer.peer_id,
            .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey([_]u8{0x7B} ** 32),
        } },
    }));

    try @import("std").testing.expectEqual(@as(u64, 12), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);
}

test "session manager promotes sessions when better paths appear" {
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(.{0x80} ** core.types.peer_id_len),
        .relay_capable = true,
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 20 },
            .preference = .relay,
        },
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 21 },
            .preference = .direct_after_signaling,
        },
    };
    var manager = SessionManager.init(&.{peer}, &sessions);

    try @import("std").testing.expect(manager.promoteHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 22 },
        .plan = .{ .direct = .{
            .peer_id = peer.peer_id,
            .node_id = @import("libmesh").Foundation.NodeId.fromPublicKey([_]u8{0x80} ** 32),
        } },
    }));
    try @import("std").testing.expectEqual(@as(u64, 22), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 20), manager.sessions.fallbackToRelay(peer.peer_id).?.session_id.value);
}

test "session manager falls back to relay when preferred paths die" {
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(.{0x81} ** core.types.peer_id_len),
        .relay_capable = true,
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 30 },
            .preference = .relay,
        },
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 31 },
            .preference = .direct,
        },
        .{
            .peer_id = peer.peer_id,
            .session_id = .{ .value = 32 },
            .preference = .direct_after_signaling,
        },
    };
    var manager = SessionManager.init(&.{peer}, &sessions);

    try @import("std").testing.expectEqual(@as(u64, 31), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 30), manager.failPreferredPath(peer.peer_id).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 30), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);
}

test "session manager handles churn promotion and failover across reconnects" {
    const libmesh = @import("libmesh");
    const peer = ManagedPeer{
        .peer_id = core.types.PeerId.init(.{0x83} ** core.types.peer_id_len),
        .relay_capable = true,
    };
    const relay_candidate = integration.libmesh_adapter.CandidatePeer{
        .peer_id = peer.peer_id,
        .node_id = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x83} ** 32),
    };
    const direct_candidate = integration.libmesh_adapter.CandidatePeer{
        .peer_id = peer.peer_id,
        .node_id = libmesh.Foundation.NodeId.fromPublicKey([_]u8{0x84} ** 32),
    };
    var sessions = [_]core.session_table.ActiveSession{
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
        .{ .peer_id = core.types.PeerId.init(.{0} ** core.types.peer_id_len), .session_id = .{ .value = 0 }, .preference = .relay },
    };
    var manager = SessionManager.withMesh(
        &.{peer},
        &sessions,
        integration.libmesh_adapter.LibmeshAdapter.withReachability(
            &.{relay_candidate},
            &.{.{ .relay = relay_candidate }},
        ),
    );

    try @import("std").testing.expectEqual(@as(usize, 1), manager.connectConfiguredPeers());
    try @import("std").testing.expectEqual(@as(u64, 1), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);

    try @import("std").testing.expect(manager.trackHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 90 },
        .plan = .{ .signaling_then_direct = direct_candidate },
    }));
    try @import("std").testing.expectEqual(@as(u64, 90), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);

    try @import("std").testing.expect(manager.promoteHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 91 },
        .plan = .{ .direct = direct_candidate },
    }));
    try @import("std").testing.expectEqual(@as(u64, 91), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);

    try @import("std").testing.expectEqual(@as(u64, 1), manager.failPreferredPath(peer.peer_id).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 1), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);

    try @import("std").testing.expect(manager.promoteHandle(peer, .{
        .peer_id = peer.peer_id,
        .session_id = .{ .value = 92 },
        .plan = .{ .direct = direct_candidate },
    }));
    try @import("std").testing.expectEqual(@as(u64, 92), manager.preferredSessionForPeer(peer.peer_id).?.session_id.value);
}
