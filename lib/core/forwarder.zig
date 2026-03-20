const linux = @import("../linux/linux.zig");
const route_table = @import("route_table.zig");
const session_table = @import("session_table.zig");
const types = @import("types.zig");

pub const Forwarder = struct {
    routes: *route_table.RouteTable,
    sessions: *session_table.SessionTable,
    tun: *linux.tun.TunDevice,
    local_peer_id: ?types.PeerId = null,

    pub fn lookupDestination(self: Forwarder, packet: []const u8) ?route_table.RouteEntry {
        if (packet.len < 20) return null;
        const destination = types.VineAddress.init(.{
            packet[16],
            packet[17],
            packet[18],
            packet[19],
        });
        return self.routes.lookup(destination);
    }

    pub fn lookupSessionForRoute(self: Forwarder, route: route_table.RouteEntry) ?session_table.ActiveSession {
        return self.sessions.preferredForPeer(route.peer_id);
    }

    pub fn forwardOutbound(self: Forwarder, packet: []const u8) ?session_table.ActiveSession {
        const route = self.lookupDestination(packet) orelse return null;
        if (self.local_peer_id) |local_peer_id| {
            if (route.peer_id.eql(local_peer_id)) return null;
        }
        return self.lookupSessionForRoute(route);
    }

    pub fn forwardInbound(self: Forwarder, source_peer_id: types.PeerId, packet: []const u8) bool {
        if (self.sessions.byPeer(source_peer_id) == null) return false;
        self.tun.writePacket(packet);
        return true;
    }

    pub fn cleanupStaleSession(self: Forwarder, peer_id: types.PeerId) bool {
        const fallback = self.sessions.fallbackToRelay(peer_id);
        if (fallback != null) return true;

        for (self.routes.entries) |*route| {
            if (route.peer_id.eql(peer_id)) {
                route.session_id = null;
                route.tombstone = true;
                return true;
            }
        }
        return false;
    }
};

test "forwarder handles route lookup, forwarding, drops, fallback, and tun injection" {
    var tun = linux.tun.TunDevice{
        .fd = 1,
    };
    var routes = [_]route_table.RouteEntry{
        .{
            .prefix = try types.VinePrefix.parse("10.8.0.0/24"),
            .peer_id = types.PeerId.init(.{2} ** types.peer_id_len),
            .session_id = .{ .value = 10 },
            .epoch = .{ .value = 1 },
            .preference = .direct,
        },
    };
    var route_state = route_table.RouteTable.init(&routes);
    var sessions = [_]session_table.ActiveSession{
        .{
            .peer_id = types.PeerId.init(.{2} ** types.peer_id_len),
            .session_id = .{ .value = 10 },
            .preference = .direct,
        },
        .{
            .peer_id = types.PeerId.init(.{2} ** types.peer_id_len),
            .session_id = .{ .value = 11 },
            .preference = .relay,
        },
    };
    var session_state = session_table.SessionTable.init(&sessions);
    const forwarder = Forwarder{
        .routes = &route_state,
        .sessions = &session_state,
        .tun = &tun,
        .local_peer_id = types.PeerId.init(.{9} ** types.peer_id_len),
    };

    const packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 8, 0, 1,
        10, 8, 0, 42,
    } ++ ([_]u8{0} ** 4);

    try @import("std").testing.expectEqual(@as(u64, 10), forwarder.forwardOutbound(&packet).?.session_id.value);
    try @import("std").testing.expect(!forwarder.forwardInbound(types.PeerId.init(.{7} ** types.peer_id_len), &packet));
    try @import("std").testing.expect(forwarder.forwardInbound(types.PeerId.init(.{2} ** types.peer_id_len), &packet));
    try @import("std").testing.expectEqualSlices(u8, &packet, tun.tx_buffer);

    try @import("std").testing.expect(forwarder.cleanupStaleSession(types.PeerId.init(.{2} ** types.peer_id_len)));

    const unknown_packet = [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        10, 9, 0, 1,
        10, 9, 0, 42,
    } ++ ([_]u8{0} ** 4);
    try @import("std").testing.expect(forwarder.forwardOutbound(&unknown_packet) == null);
}
