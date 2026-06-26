const std = @import("std");
const Io = std.Io;

const hex_chars = "0123456789abcdef";

/// RFC 4122 UUID. v4() generates a random one; toBuf()/parse() convert
/// to/from the standard 36-char hyphenated hex form.
pub const Uuid = struct {
    bytes: [16]u8,

    pub fn v4(io: Io) Uuid {
        var bytes: [16]u8 = undefined;
        Io.random(io, &bytes);
        bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
        return .{ .bytes = bytes };
    }

    /// Writes the 36-char hyphenated lowercase form into `buf` and returns
    /// the written slice.
    pub fn toBuf(self: *const Uuid, buf: *[36]u8) []const u8 {
        var pos: usize = 0;
        for (self.bytes, 0..) |b, i| {
            if (i == 4 or i == 6 or i == 8 or i == 10) {
                buf[pos] = '-';
                pos += 1;
            }
            buf[pos] = hex_chars[b >> 4];
            buf[pos + 1] = hex_chars[b & 0x0F];
            pos += 2;
        }
        return buf[0..pos];
    }

    pub fn parse(s: []const u8) !Uuid {
        if (s.len != 36) return error.InvalidUuid;
        for ([_]usize{ 8, 13, 18, 23 }) |p| {
            if (s[p] != '-') return error.InvalidUuid;
        }

        var bytes: [16]u8 = undefined;
        var byte_i: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '-') {
                i += 1;
                continue;
            }
            const hi = try hexVal(s[i]);
            const lo = try hexVal(s[i + 1]);
            bytes[byte_i] = (hi << 4) | lo;
            byte_i += 1;
            i += 2;
        }
        return .{ .bytes = bytes };
    }

    pub fn eql(a: Uuid, b: Uuid) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }
};

fn hexVal(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidUuid,
    };
}

test "v4 sets the version nibble to 4 and variant bits to 10xx" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const id = Uuid.v4(io);
    try std.testing.expectEqual(@as(u8, 0x4), id.bytes[6] >> 4);
    try std.testing.expectEqual(@as(u8, 0x2), id.bytes[8] >> 6);
}

test "two v4 calls produce different UUIDs" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const a = Uuid.v4(io);
    const b = Uuid.v4(io);
    try std.testing.expect(!a.eql(b));
}

test "toBuf formats as 8-4-4-4-12 hyphenated lowercase hex" {
    const id = Uuid{ .bytes = .{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef } };
    var buf: [36]u8 = undefined;
    const s = id.toBuf(&buf);
    try std.testing.expectEqualStrings("01234567-89ab-cdef-0123-456789abcdef", s);
}

test "parse(toBuf(x)) round-trips to the same bytes" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const original = Uuid.v4(io);
    var buf: [36]u8 = undefined;
    const s = original.toBuf(&buf);

    const parsed = try Uuid.parse(s);
    try std.testing.expect(original.eql(parsed));
}

test "parse rejects the wrong length" {
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("too-short"));
}

test "parse rejects hyphens in the wrong place" {
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("0123456789ab-cdef-0123-456789abcdef0"));
}

test "parse rejects non-hex characters" {
    try std.testing.expectError(error.InvalidUuid, Uuid.parse("zzzzzzzz-89ab-cdef-0123-456789abcdef"));
}
