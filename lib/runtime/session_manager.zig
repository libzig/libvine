const core = @import("../core/core.zig");

pub const ManagedPeer = struct {
    peer_id: core.types.PeerId,
    relay_capable: bool = false,
};

pub const SessionManager = struct {
    configured_peers: []const ManagedPeer = &.{},
    sessions: core.session_table.SessionTable,

    pub fn init(
        configured_peers: []const ManagedPeer,
        session_buffer: []core.session_table.ActiveSession,
    ) SessionManager {
        return .{
            .configured_peers = configured_peers,
            .sessions = core.session_table.SessionTable.init(session_buffer),
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
