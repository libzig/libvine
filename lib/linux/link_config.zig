const types = @import("../core/types.zig");

pub const LinkState = struct {
    ifname: [16]u8 = [_]u8{0} ** 16,
    address: ?types.VineAddress = null,
    prefix_len: ?u8 = null,
    up: bool = false,
};

pub fn assignAddress(state: *LinkState, address: types.VineAddress, prefix_len: u8) void {
    state.address = address;
    state.prefix_len = prefix_len;
}

pub fn bringUp(state: *LinkState) void {
    state.up = true;
}

test "link config assigns address and marks interface up" {
    var state = LinkState{};
    assignAddress(&state, types.VineAddress.init(.{ 10, 1, 0, 1 }), 24);
    bringUp(&state);

    try @import("std").testing.expect(state.address.?.eql(types.VineAddress.init(.{ 10, 1, 0, 1 })));
    try @import("std").testing.expectEqual(@as(u8, 24), state.prefix_len.?);
    try @import("std").testing.expect(state.up);
}
