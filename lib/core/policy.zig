const membership = @import("membership.zig");
const types = @import("types.zig");

pub const AdmissionPolicy = struct {
    allowed_peers: []const types.PeerId = &.{},

    pub fn allows(self: AdmissionPolicy, peer_id: types.PeerId) bool {
        for (self.allowed_peers) |allowed| {
            if (allowed.eql(peer_id)) return true;
        }
        return false;
    }
};

pub const PrefixPolicy = struct {
    pub fn allows(_: PrefixPolicy, _: membership.PeerMembership) bool {
        return true;
    }
};
