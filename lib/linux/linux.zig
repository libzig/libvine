pub const link_config = @import("link_config.zig");
pub const routes = @import("routes.zig");
pub const tun = @import("tun.zig");

test {
    _ = link_config;
    _ = routes;
    _ = tun;
}
