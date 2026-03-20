const types = @import("types.zig");

pub const PeerPolicyFlags = packed struct(u8) {
    can_forward: bool = true,
    can_advertise: bool = true,
    reserved: u6 = 0,
};

pub const PeerMembership = struct {
    peer_id: types.PeerId,
    prefix: types.VinePrefix,
    epoch: types.MembershipEpoch,
    flags: PeerPolicyFlags = .{},
    announced_at_ms: i64,
    expires_at_ms: ?i64 = null,
};
