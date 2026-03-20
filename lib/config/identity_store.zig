const std = @import("std");
const libself = @import("libself");
const identity_adapter = @import("../integration/identity_adapter.zig");

pub const file_magic = "libvine-identity-v1";
pub const expected_dir_mode: u32 = 0o700;
pub const expected_file_mode: u32 = 0o600;
pub const field_format = "format";
pub const field_seed = "seed";
pub const field_public_key = "public_key";
pub const field_peer_id = "peer_id";
pub const field_fingerprint = "fingerprint";
pub const StoreError = error{
    MissingIdentityFile,
    InvalidIdentityFile,
};

pub const StoredIdentity = struct {
    seed: [32]u8,
    bound: identity_adapter.BoundIdentity,
};

pub fn generate() !StoredIdentity {
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);
    return fromSeed(seed);
}

pub fn fromSeed(seed: [32]u8) !StoredIdentity {
    const key_pair = try libself.identity.KeyPair.fromSeed(seed);
    return .{
        .seed = seed,
        .bound = identity_adapter.bindKeyPair(key_pair),
    };
}

pub fn encode(allocator: std.mem.Allocator, stored: StoredIdentity) ![]u8 {
    const seed_hex = std.fmt.bytesToHex(stored.seed, .lower);
    const public_key_hex = std.fmt.bytesToHex(stored.bound.key_pair.public_key, .lower);
    const fingerprint_hex = stored.bound.node_id.toHex();
    return std.fmt.allocPrint(
        allocator,
        "format={s}\nseed={s}\npublic_key={s}\npeer_id={f}\nfingerprint={s}\n",
        .{
            file_magic,
            &seed_hex,
            &public_key_hex,
            stored.bound.peer_id,
            &fingerprint_hex,
        },
    );
}

pub fn decode(data: []const u8) StoreError!StoredIdentity {
    var maybe_seed: ?[32]u8 = null;
    var saw_magic = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, '=');
        const key = parts.next() orelse continue;
        const value = parts.next() orelse continue;

        if (std.mem.eql(u8, key, "format")) {
            saw_magic = std.mem.eql(u8, value, file_magic);
        } else if (std.mem.eql(u8, key, "seed")) {
            maybe_seed = try parseHex32(value);
        }
    }

    if (!saw_magic or maybe_seed == null) return StoreError.InvalidIdentityFile;
    return fromSeed(maybe_seed.?) catch StoreError.InvalidIdentityFile;
}

pub fn writeFile(path: []const u8, stored: StoredIdentity) !void {
    const allocator = std.heap.page_allocator;
    const encoded = try encode(allocator, stored);
    defer allocator.free(encoded);

    try ensureParentDir(path);
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true, .mode = expected_file_mode })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true, .mode = expected_file_mode });
    defer file.close();

    try file.writeAll(encoded);
}

pub fn generateAndWrite(path: []const u8) !StoredIdentity {
    const stored = try generate();
    try writeFile(path, stored);
    return stored;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) StoreError!StoredIdentity {
    const file = if (std.fs.path.isAbsolute(path))
        std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return StoreError.MissingIdentityFile,
            else => return StoreError.InvalidIdentityFile,
        }
    else
        std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return StoreError.MissingIdentityFile,
            else => return StoreError.InvalidIdentityFile,
        };
    defer file.close();

    const data = file.readToEndAlloc(allocator, 4096) catch return StoreError.InvalidIdentityFile;
    defer allocator.free(data);
    return decode(data);
}

pub fn loadBoundIdentity(allocator: std.mem.Allocator, path: []const u8) StoreError!identity_adapter.BoundIdentity {
    return (try readFile(allocator, path)).bound;
}

fn parseHex32(text: []const u8) StoreError![32]u8 {
    if (text.len != 64) return StoreError.InvalidIdentityFile;

    var bytes: [32]u8 = undefined;
    for (0..32) |i| {
        bytes[i] = std.fmt.parseInt(u8, text[i * 2 .. i * 2 + 2], 16) catch return StoreError.InvalidIdentityFile;
    }
    return bytes;
}

fn ensureParentDir(path: []const u8) !void {
    const dirname = std.fs.path.dirname(path) orelse return;
    if (dirname.len == 0) return;

    if (std.fs.path.isAbsolute(path)) {
        var root = try std.fs.openDirAbsolute("/", .{});
        defer root.close();
        try root.makePath(dirname[1..]);
    } else {
        try std.fs.cwd().makePath(dirname);
    }
}

test "identity store encodes and decodes persisted seed identity" {
    const allocator = std.testing.allocator;
    const stored = try fromSeed([_]u8{0x11} ** 32);
    const encoded = try encode(allocator, stored);
    defer allocator.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqualSlices(u8, &stored.seed, &decoded.seed);
    try std.testing.expectEqualSlices(u8, &stored.bound.key_pair.public_key, &decoded.bound.key_pair.public_key);
    try std.testing.expect(stored.bound.peer_id.eql(decoded.bound.peer_id));
}

test "identity store serialized format and permission expectations stay stable" {
    const allocator = std.testing.allocator;
    const stored = try fromSeed([_]u8{0x22} ** 32);
    const encoded = try encode(allocator, stored);
    defer allocator.free(encoded);

    try std.testing.expect(std.mem.indexOf(u8, encoded, field_format ++ "=" ++ file_magic) != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, field_seed ++ "=") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, field_public_key ++ "=") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, field_peer_id ++ "=") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, field_fingerprint ++ "=") != null);
    try std.testing.expectEqual(@as(u32, 0o700), expected_dir_mode);
    try std.testing.expectEqual(@as(u32, 0o600), expected_file_mode);
}

test "identity store writes generated identities to disk" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const full_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/state/identity.txt", .{tmp_path});
    defer std.testing.allocator.free(full_path);

    const stored = try generateAndWrite(full_path);
    _ = stored;

    var file = try tmp.dir.openFile("state/identity.txt", .{});
    defer file.close();

    var buffer: [512]u8 = undefined;
    const len = try file.readAll(&buffer);
    try std.testing.expect(std.mem.indexOf(u8, buffer[0..len], file_magic) != null);
}

test "identity store rejects missing and malformed files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try std.testing.expectError(StoreError.MissingIdentityFile, readFile(std.testing.allocator, "does-not-exist.identity"));

    try tmp.dir.writeFile(.{ .sub_path = "bad.identity", .data = "format=wrong\nseed=oops\n" });
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const full_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/bad.identity", .{tmp_path});
    defer std.testing.allocator.free(full_path);

    try std.testing.expectError(StoreError.InvalidIdentityFile, readFile(std.testing.allocator, full_path));
}

test "identity store binds peer id directly from persisted libself material" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const full_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/identity.txt", .{tmp_path});
    defer std.testing.allocator.free(full_path);

    const stored = try fromSeed([_]u8{0x33} ** 32);
    try writeFile(full_path, stored);

    const bound = try loadBoundIdentity(std.testing.allocator, full_path);
    try std.testing.expect(bound.peer_id.eql(stored.bound.peer_id));
    try std.testing.expectEqualSlices(u8, &bound.key_pair.public_key, &stored.bound.key_pair.public_key);
}

test "identity lifecycle keeps peer id and fingerprint stable across reload" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const full_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/stable.identity", .{tmp_path});
    defer std.testing.allocator.free(full_path);

    const created = try generateAndWrite(full_path);
    const reloaded = try readFile(std.testing.allocator, full_path);

    try std.testing.expect(created.bound.peer_id.eql(reloaded.bound.peer_id));
    try std.testing.expectEqualSlices(u8, &created.bound.node_id.toBytes(), &reloaded.bound.node_id.toBytes());
    try std.testing.expectEqualSlices(u8, &created.bound.node_id.toHex(), &reloaded.bound.node_id.toHex());
}
