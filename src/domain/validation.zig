const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_content_codepoints: usize = 300;
pub const password_min_len: usize = 8;
pub const password_max_len: usize = 128;

pub const LengthResult = union(enum) {
    ok,
    too_short,
    too_long,
    invalid_utf8,
};

pub fn validateLength(text: []const u8, min: usize, max: usize) LengthResult {
    const count = std.unicode.utf8CountCodepoints(text) catch return .invalid_utf8;
    if (count < min) return .too_short;
    if (count > max) return .too_long;
    return .ok;
}

pub const ContentResult = union(enum) {
    ok: []const u8,
    too_short,
    too_long,
    invalid_utf8,
};

pub fn sanitizeContent(raw: []const u8) ContentResult {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    return switch (validateLength(trimmed, 1, max_content_codepoints)) {
        .ok => .{ .ok = trimmed },
        .too_short => .too_short,
        .too_long => .too_long,
        .invalid_utf8 => .invalid_utf8,
    };
}

pub const PasswordResult = union(enum) {
    ok,
    too_short,
    too_long,
    whitespace,
    non_ascii,
    invalid_utf8,
};

pub fn validatePassword(password: []const u8) PasswordResult {
    for (password) |byte| {
        if (byte > 0x7F) return .non_ascii;
        if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r') return .whitespace;
    }
    return switch (validateLength(password, password_min_len, password_max_len)) {
        .ok => .ok,
        .too_short => .too_short,
        .too_long => .too_long,
        .invalid_utf8 => .invalid_utf8,
    };
}

test "validateLength checks min and max" {
    try std.testing.expectEqual(LengthResult.too_short, validateLength("", 1, 10));
    try std.testing.expectEqual(LengthResult.ok, validateLength("a", 1, 10));
    try std.testing.expectEqual(LengthResult.ok, validateLength("1234567890", 1, 10));
    try std.testing.expectEqual(LengthResult.too_long, validateLength("1234567890a", 1, 10));
}

test "validateLength treats invalid UTF-8 as invalid_utf8" {
    // 0xFF is not a valid UTF-8 start byte.
    const invalid = &[_]u8{ 0xFF, 0xFE };
    try std.testing.expectEqual(LengthResult.invalid_utf8, validateLength(invalid, 1, 10));
}

fn repeatString(allocator: Allocator, s: []const u8, n: usize) ![]u8 {
    const result = try allocator.alloc(u8, s.len * n);
    for (0..n) |i| {
        for (s, 0..) |byte, j| {
            result[i * s.len + j] = byte;
        }
    }
    return result;
}

test "sanitizeContent trims and validates length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = sanitizeContent("  hello world  ");
    try std.testing.expectEqual(ContentResult.ok, std.meta.activeTag(result));
    try std.testing.expectEqualStrings("hello world", result.ok);

    try std.testing.expectEqual(ContentResult.too_short, sanitizeContent(""));
    try std.testing.expectEqual(ContentResult.too_short, sanitizeContent("   "));

    const exactly_300 = try repeatString(allocator, "中", 300);
    const ok_result = sanitizeContent(exactly_300);
    try std.testing.expectEqual(ContentResult.ok, std.meta.activeTag(ok_result));

    const over_300 = try repeatString(allocator, "中", 301);
    try std.testing.expectEqual(ContentResult.too_long, sanitizeContent(over_300));
}

test "validatePassword enforces ASCII, whitespace, and length rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(PasswordResult.too_short, validatePassword("1234567"));
    try std.testing.expectEqual(PasswordResult.ok, validatePassword("Admin0001"));
    try std.testing.expectEqual(PasswordResult.ok, validatePassword("Admin_0001-"));

    const long_ok = try repeatString(allocator, "a", 128);
    try std.testing.expectEqual(PasswordResult.ok, validatePassword(long_ok));

    const too_long = try repeatString(allocator, "a", 129);
    try std.testing.expectEqual(PasswordResult.too_long, validatePassword(too_long));

    try std.testing.expectEqual(PasswordResult.whitespace, validatePassword("Admin 0001"));
    try std.testing.expectEqual(PasswordResult.whitespace, validatePassword("Admin\t0001"));
    try std.testing.expectEqual(PasswordResult.whitespace, validatePassword("Admin\n0001"));
    try std.testing.expectEqual(PasswordResult.whitespace, validatePassword("Admin\r0001"));

    try std.testing.expectEqual(PasswordResult.non_ascii, validatePassword("Admín0001"));
}
