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
            if (self.putSession(.{
                .peer_id = handle.peer_id,
                .session_id = handle.session_id,
                .preference = preferenceForPlan(handle.plan),
            })) {
                connected += 1;
            }
        }
        return connected;
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
