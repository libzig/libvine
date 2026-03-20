const linux = @import("../linux/linux.zig");
const route_table = @import("route_table.zig");
const session_table = @import("session_table.zig");
const types = @import("types.zig");

pub const Forwarder = struct {
    routes: *route_table.RouteTable,
    sessions: *session_table.SessionTable,
    tun: *linux.tun.TunDevice,

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
        return self.lookupSessionForRoute(route);
    }

    pub fn forwardInbound(self: Forwarder, packet: []const u8) void {
        self.tun.writePacket(packet);
    }
};
