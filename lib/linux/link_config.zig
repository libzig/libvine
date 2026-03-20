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
