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

    pub fn promote(self: *SessionTable, replacement: ActiveSession) bool {
        var preferred_index: ?usize = null;
        var preferred_preference: ?route_table.RouteEntry.Preference = null;

        for (self.sessions, 0..) |session, index| {
            if (!session.peer_id.eql(replacement.peer_id)) continue;
            if (session.preference == .relay) continue;

            if (preferred_index == null or @intFromEnum(session.preference) > @intFromEnum(preferred_preference.?)) {
                preferred_index = index;
                preferred_preference = session.preference;
            }
        }

        if (preferred_index) |index| {
            if (@intFromEnum(replacement.preference) >= @intFromEnum(self.sessions[index].preference)) {
                self.sessions[index] = replacement;
                return true;
            }
        }

        for (self.sessions) |*session| {
            if (!session.peer_id.eql(replacement.peer_id)) continue;
            if (@intFromEnum(replacement.preference) > @intFromEnum(session.preference)) {
                session.* = replacement;
                return true;
            }
        }
        return false;
    }

    pub fn fallbackToRelay(self: *SessionTable, peer_id: types.PeerId) ?ActiveSession {
        for (self.sessions) |session| {
            if (session.peer_id.eql(peer_id) and session.preference == .relay) return session;
        }
        return null;
    }
};

test "session table indexes, promotion, and relay fallback work" {
    var sessions = [_]ActiveSession{
        .{
            .peer_id = types.PeerId.init(.{1} ** types.peer_id_len),
            .session_id = .{ .value = 1 },
            .preference = .relay,
        },
        .{
            .peer_id = types.PeerId.init(.{1} ** types.peer_id_len),
            .session_id = .{ .value = 2 },
            .preference = .direct,
        },
    };
    var table = SessionTable.init(&sessions);

    try @import("std").testing.expectEqual(@as(u64, 1), table.bySessionId(.{ .value = 1 }).?.session_id.value);
    try @import("std").testing.expectEqual(route_table.RouteEntry.Preference.direct, table.preferredForPeer(types.PeerId.init(.{1} ** types.peer_id_len)).?.preference);

    try @import("std").testing.expect(table.promote(.{
        .peer_id = types.PeerId.init(.{1} ** types.peer_id_len),
        .session_id = .{ .value = 3 },
        .preference = .direct,
    }));
    try @import("std").testing.expectEqual(@as(u64, 3), table.preferredForPeer(types.PeerId.init(.{1} ** types.peer_id_len)).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 1), table.fallbackToRelay(types.PeerId.init(.{1} ** types.peer_id_len)).?.session_id.value);
}

test "session table churn preserves direct preference and relay fallback" {
    const peer = types.PeerId.init(.{0x66} ** types.peer_id_len);
    var sessions = [_]ActiveSession{
        .{
            .peer_id = peer,
            .session_id = .{ .value = 10 },
            .preference = .relay,
        },
        .{
            .peer_id = peer,
            .session_id = .{ .value = 11 },
            .preference = .direct_after_signaling,
        },
    };
    var table = SessionTable.init(&sessions);

    try @import("std").testing.expectEqual(@as(u64, 11), table.preferredForPeer(peer).?.session_id.value);
    try @import("std").testing.expect(table.promote(.{
        .peer_id = peer,
        .session_id = .{ .value = 12 },
        .preference = .direct,
    }));
    try @import("std").testing.expectEqual(@as(u64, 12), table.preferredForPeer(peer).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 10), table.fallbackToRelay(peer).?.session_id.value);

    sessions[1] = .{
        .peer_id = peer,
        .session_id = .{ .value = 13 },
        .preference = .direct_after_signaling,
    };
    try @import("std").testing.expectEqual(@as(u64, 13), table.preferredForPeer(peer).?.session_id.value);
    try @import("std").testing.expectEqual(@as(u64, 10), table.fallbackToRelay(peer).?.session_id.value);
}
