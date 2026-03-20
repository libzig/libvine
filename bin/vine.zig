const std = @import("std");

pub fn main() !void {
    const stderr = std.fs.File.stderr().writer(&.{});
    try stderr.interface.writeAll("vine: CLI entrypoint not implemented yet\n");
}
