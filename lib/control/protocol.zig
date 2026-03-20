const types = @import("../core/types.zig");

pub const CapabilityFlags = packed struct(u8) {
    relay_capable: bool = false,
    direct_capable: bool = true,
    diagnostic_capable: bool = false,
    reserved: u5 = 0,
};

pub const Hello = struct {
    network_id: types.NetworkId,
    version_major: u16,
    version_minor: u16,
    capabilities: CapabilityFlags = .{},
};

pub const JoinAnnounce = struct {
    network_id: types.NetworkId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};

pub const RouteUpdate = struct {
    network_id: types.NetworkId,
    owner: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
};
