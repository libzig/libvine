const libself = @import("libself");
const types = @import("../core/types.zig");

pub const BoundIdentity = struct {
    peer_id: types.PeerId,
    node_id: libself.NodeId,
    key_pair: libself.identity.KeyPair,
};

pub fn bindKeyPair(key_pair: libself.identity.KeyPair) BoundIdentity {
    const node_id = libself.NodeId.fromPublicKey(key_pair.public_key);
    return .{
        .peer_id = types.PeerId.init(node_id.toBytes()),
        .node_id = node_id,
        .key_pair = key_pair,
    };
}
