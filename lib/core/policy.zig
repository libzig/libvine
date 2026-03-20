const membership = @import("membership.zig");
const types = @import("types.zig");

pub const AdmissionPolicy = struct {
    pub fn allows(_: AdmissionPolicy, _: types.PeerId) bool {
        return true;
    }
};

pub const PrefixPolicy = struct {
    pub fn allows(_: PrefixPolicy, _: membership.PeerMembership) bool {
        return true;
    }
};
