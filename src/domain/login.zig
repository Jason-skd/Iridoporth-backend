const std = @import("std");
const Allocator = std.mem.Allocator;
const argon2 = std.crypto.pwhash.argon2;

const LoginResult = union(enum) {
    success: u64,
    failure: void,
};

pub fn hashPassword(io: std.Io, allocator: Allocator, password: []const u8) ![]const u8 {
    var buf: [128]u8 = undefined;
    const password_hash = try argon2.strHash(
        password,
        .{
            .allocator = allocator,
            .params = argon2.Params.owasp_2id,
            .mode = .argon2id,
        },
        &buf,
        io,
    );

    return allocator.dupe(u8, password_hash);
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
