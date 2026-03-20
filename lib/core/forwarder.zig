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
};
