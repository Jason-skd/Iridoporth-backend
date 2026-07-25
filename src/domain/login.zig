const std = @import("std");
const Allocator = std.mem.Allocator;
const argon2 = std.crypto.pwhash.argon2;

pub const LoginResult = union(enum) {
    success: i64,
    failure: void,
};

pub fn hashPassword(
    io: std.Io,
    allocator: Allocator,
    password: []const u8,
    out: *[128]u8,
) ![]const u8 {
    return argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = argon2.Params.owasp_2id,
            .mode = .argon2id,
        },
        out,
        io,
    );
}

pub fn verifyPassword(
    io: std.Io,
    allocator: Allocator,
    stored_password_hash: []const u8,
    password: []const u8,
) !bool {
    argon2.strVerify(
        stored_password_hash,
        password,
        .{ .allocator = allocator },
        io,
    ) catch |err| switch (err) {
        error.PasswordVerificationFailed => return false,
        else => return err,
    };

    return true;
}
