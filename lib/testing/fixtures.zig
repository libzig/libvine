const core = @import("../core/core.zig");

pub const sample_network_name = "fixture-net";

pub fn networkId() !core.types.NetworkId {
    return core.types.NetworkId.init(sample_network_name);
}

pub fn peerId(byte: u8) core.types.PeerId {
    return core.types.PeerId.init(.{byte} ** core.types.peer_id_len);
}

pub fn prefix(text: []const u8) !core.types.VinePrefix {
    return core.types.VinePrefix.parse(text);
}

pub fn packet(src: [4]u8, dst: [4]u8) [24]u8 {
    return [_]u8{
        0x45, 0x00, 0x00, 0x14,
        0x00, 0x00, 0x00, 0x00,
        0x40, 0x00, 0x00, 0x00,
        src[0], src[1], src[2], src[3],
        dst[0], dst[1], dst[2], dst[3],
    } ++ ([_]u8{0} ** 4);
}

test "fixtures expose reusable ids prefixes and packets" {
    const id = try networkId();
    try @import("std").testing.expectEqualStrings(sample_network_name, id.encode());
    try @import("std").testing.expect(peerId(0xaa).eql(core.types.PeerId.init(.{0xaa} ** core.types.peer_id_len)));
    try @import("std").testing.expect((try prefix("10.91.0.0/24")).contains(core.types.VineAddress.init(.{ 10, 91, 0, 7 })));
    try @import("std").testing.expectEqual(@as(u8, 10), packet(.{ 10, 1, 0, 1 }, .{ 10, 2, 0, 1 })[12]);
}
