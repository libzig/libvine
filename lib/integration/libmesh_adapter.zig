const libmesh = @import("libmesh");
const types = @import("../core/types.zig");

pub const CandidatePeer = struct {
    peer_id: types.PeerId,
    node_id: libmesh.Foundation.NodeId,
};

pub const LibmeshAdapter = struct {
    pub fn init() LibmeshAdapter {
        return .{};
    }
};
