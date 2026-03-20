const VineError = @import("../common/error.zig").VineError;
const types = @import("../core/types.zig");

pub const TunConfig = struct {
    ifname: [16]u8 = [_]u8{0} ** 16,
    local_address: types.VineAddress,
    prefix_len: u8,
    mtu: u16 = 1400,
};

pub const TunDevice = struct {
    fd: i32 = -1,
    ifname: [16]u8 = [_]u8{0} ** 16,
    config: ?TunConfig = null,

    pub fn open() VineError!TunDevice {
        return .{ .fd = 1 };
    }

    pub fn configure(self: *TunDevice, request: IfReq) void {
        self.ifname = request.name;
    }

    pub fn applyConfig(self: *TunDevice, config: TunConfig) void {
        self.ifname = config.ifname;
        self.config = config;
    }
};

pub const IfReq = struct {
    name: [16]u8 = [_]u8{0} ** 16,
    flags: u16 = 0,
};

pub const IFF_TUN: u16 = 0x0001;
pub const IFF_NO_PI: u16 = 0x1000;

pub fn mapOpenError(errno: u16) VineError {
    return switch (errno) {
        2 => VineError.LinuxUnavailable,
        13 => VineError.LinuxPermissionDenied,
        else => VineError.LinuxUnavailable,
    };
}
