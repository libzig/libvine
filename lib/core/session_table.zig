const route_table = @import("route_table.zig");
const types = @import("types.zig");

pub const ActiveSession = struct {
    peer_id: types.PeerId,
    session_id: types.SessionId,
    preference: route_table.RouteEntry.Preference,
};

pub const SessionTable = struct {
    sessions: []ActiveSession,

    pub fn init(sessions: []ActiveSession) SessionTable {
        return .{ .sessions = sessions };
    }

    pub fn byPeer(self: SessionTable, peer_id: types.PeerId) ?ActiveSession {
        for (self.sessions) |session| {
            if (session.peer_id.eql(peer_id)) return session;
        }
        return null;
    }

    pub fn bySessionId(self: SessionTable, session_id: types.SessionId) ?ActiveSession {
        for (self.sessions) |session| {
            if (session.session_id.eql(session_id)) return session;
        }
        return null;
    }

    pub fn preferredForPeer(self: SessionTable, peer_id: types.PeerId) ?ActiveSession {
        var selected: ?ActiveSession = null;
        for (self.sessions) |session| {
            if (!session.peer_id.eql(peer_id)) continue;
            if (selected == null or @intFromEnum(session.preference) > @intFromEnum(selected.?.preference)) {
                selected = session;
            }
        }
        return selected;
    }
};
