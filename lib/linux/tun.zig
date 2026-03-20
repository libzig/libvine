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
    rx_buffer: []const u8 = &.{},
    tx_buffer: []const u8 = &.{},

    pub fn open() VineError!TunDevice {
        return .{ .fd = 1 };
    }

    pub fn configure(self: *TunDevice, request: IfReq) void {
        self.ifname = request.name;
    }

    pub fn close(self: *TunDevice) void {
        self.fd = -1;
        self.rx_buffer = &.{};
        self.tx_buffer = &.{};
    }

    pub fn applyConfig(self: *TunDevice, config: TunConfig) void {
        self.ifname = config.ifname;
        self.config = config;
    }

    pub fn loadReadBuffer(self: *TunDevice, rx_buffer: []const u8) void {
        self.rx_buffer = rx_buffer;
    }

    pub fn readPacket(self: *TunDevice) ?[]const u8 {
        if (self.rx_buffer.len == 0) return null;
        defer self.rx_buffer = &.{};
        return self.rx_buffer;
    }

    pub fn writePacket(self: *TunDevice, packet: []const u8) void {
        self.tx_buffer = packet;
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

test "tun open error mapping and configuration work" {
    try @import("std").testing.expectEqual(VineError.LinuxUnavailable, mapOpenError(2));
    try @import("std").testing.expectEqual(VineError.LinuxPermissionDenied, mapOpenError(13));

    var device = try TunDevice.open();
    var ifreq = IfReq{};
    ifreq.name[0] = 'v';
    ifreq.name[1] = 'n';
    ifreq.flags = IFF_TUN | IFF_NO_PI;
    device.configure(ifreq);
    try @import("std").testing.expectEqual(@as(u8, 'v'), device.ifname[0]);

    const config = TunConfig{
        .ifname = ifreq.name,
        .local_address = types.VineAddress.init(.{ 10, 1, 0, 1 }),
        .prefix_len = 24,
        .mtu = 1400,
    };
    device.applyConfig(config);
    try @import("std").testing.expectEqual(@as(u16, 1400), device.config.?.mtu);
}

test "tun read and write buffers are testable" {
    var device = try TunDevice.open();
    const packet = [_]u8{ 0x45, 0x00, 0x00, 0x14 } ++ ([_]u8{0} ** 16);
    device.loadReadBuffer(&packet);
    try @import("std").testing.expectEqualSlices(u8, &packet, device.readPacket().?);
    try @import("std").testing.expect(device.readPacket() == null);

    device.writePacket(&packet);
    try @import("std").testing.expectEqualSlices(u8, &packet, device.tx_buffer);
}

test "tun handles short reads teardown and reopen cycles" {
    var device = try TunDevice.open();
    const short_packet = [_]u8{ 0x45, 0x00, 0x00, 0x14 };
    device.loadReadBuffer(&short_packet);
    try @import("std").testing.expectEqualSlices(u8, &short_packet, device.readPacket().?);

    device.close();
    try @import("std").testing.expectEqual(@as(i32, -1), device.fd);
    try @import("std").testing.expect(device.readPacket() == null);

    device = try TunDevice.open();
    try @import("std").testing.expectEqual(@as(i32, 1), device.fd);
    device.close();
    device = try TunDevice.open();
    try @import("std").testing.expectEqual(@as(i32, 1), device.fd);
}
