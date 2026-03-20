const libmesh = @import("libmesh");
const types = @import("../core/types.zig");

pub const CandidatePeer = struct {
    peer_id: types.PeerId,
    node_id: libmesh.Foundation.NodeId,
};

pub const ReachabilityPlan = union(enum) {
    direct: CandidatePeer,
    signaling_then_direct: CandidatePeer,
    relay: CandidatePeer,
};

pub const SessionHandle = struct {
    peer_id: types.PeerId,
    session_id: types.SessionId,
    plan: ReachabilityPlan,
};

pub const LibmeshAdapter = struct {
    candidates: []const CandidatePeer = &.{},
    plans: []const ReachabilityPlan = &.{},

    pub fn init() LibmeshAdapter {
        return .{};
    }

    pub fn withCandidates(candidates: []const CandidatePeer) LibmeshAdapter {
        return .{ .candidates = candidates };
    }

    pub fn withReachability(
        candidates: []const CandidatePeer,
        plans: []const ReachabilityPlan,
    ) LibmeshAdapter {
        return .{
            .candidates = candidates,
            .plans = plans,
        };
    }

    pub fn resolvePeerByIdentity(self: LibmeshAdapter, peer_id: types.PeerId) ?CandidatePeer {
        for (self.candidates) |candidate| {
            if (candidate.peer_id.eql(peer_id)) return candidate;
        }
        return null;
    }

    pub fn resolveReachability(self: LibmeshAdapter, peer_id: types.PeerId) ?ReachabilityPlan {
        for (self.plans) |plan| {
            const candidate = switch (plan) {
                .direct => |value| value,
                .signaling_then_direct => |value| value,
                .relay => |value| value,
            };
            if (candidate.peer_id.eql(peer_id)) return plan;
        }
        return null;
    }

    pub fn connectPeer(self: LibmeshAdapter, peer_id: types.PeerId) ?SessionHandle {
        const plan = self.resolveReachability(peer_id) orelse return null;
        return .{
            .peer_id = peer_id,
            .session_id = .{ .value = 1 },
            .plan = plan,
        };
    }

    pub fn openSession(self: LibmeshAdapter, peer_id: types.PeerId) ?SessionHandle {
        return self.connectPeer(peer_id);
    }
};
