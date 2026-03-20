const linux = @import("../linux/linux.zig");
const route_table = @import("route_table.zig");
const session_table = @import("session_table.zig");

pub const Forwarder = struct {
    routes: *route_table.RouteTable,
    sessions: *session_table.SessionTable,
    tun: *linux.tun.TunDevice,
};
