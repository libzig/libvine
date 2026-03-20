const types = @import("types.zig");

pub const RouteEntry = struct {
    prefix: types.VinePrefix,
    peer_id: types.PeerId,
    session_id: ?types.SessionId = null,
    epoch: types.MembershipEpoch,
};

pub const RouteTable = struct {
    entries: []RouteEntry = &.{},
};
