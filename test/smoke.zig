const std = @import("std");
const libvine = @import("libvine");

test "libvine public imports compile" {
    _ = libvine.api;
    _ = libvine.common;
    _ = libvine.control;
    _ = libvine.core;
    _ = libvine.data;
    _ = libvine.integration;
    _ = libvine.linux;
    _ = libvine.testing;

    try std.testing.expect(true);
}
