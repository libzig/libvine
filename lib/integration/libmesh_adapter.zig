const libmesh = @import("libmesh");
const types = @import("../core/types.zig");

pub const CandidatePeer = struct {
    peer_id: types.PeerId,
    node_id: libmesh.Foundation.NodeId,
};

pub const LibmeshAdapter = struct {
    candidates: []const CandidatePeer = &.{},

    pub fn init() LibmeshAdapter {
        return .{};
    }

    pub fn withCandidates(candidates: []const CandidatePeer) LibmeshAdapter {
        return .{ .candidates = candidates };
    }

    pub fn resolvePeerByIdentity(self: LibmeshAdapter, peer_id: types.PeerId) ?CandidatePeer {
        for (self.candidates) |candidate| {
            if (candidate.peer_id.eql(peer_id)) return candidate;
        }
        return null;
    }
};
