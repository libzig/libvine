const std = @import("std");

pub const Subcommand = enum {
    init,
    show,
    export_public,
    fingerprint,
};

pub fn parseSubcommand(arg: []const u8) ?Subcommand {
    if (std.mem.eql(u8, arg, "init")) return .init;
    if (std.mem.eql(u8, arg, "show")) return .show;
    if (std.mem.eql(u8, arg, "export-public")) return .export_public;
    if (std.mem.eql(u8, arg, "fingerprint")) return .fingerprint;
    return null;
}

test "identity CLI subcommands parse" {
    try std.testing.expectEqual(Subcommand.init, parseSubcommand("init").?);
    try std.testing.expectEqual(Subcommand.show, parseSubcommand("show").?);
    try std.testing.expectEqual(Subcommand.export_public, parseSubcommand("export-public").?);
    try std.testing.expectEqual(Subcommand.fingerprint, parseSubcommand("fingerprint").?);
    try std.testing.expect(parseSubcommand("rotate") == null);
}
