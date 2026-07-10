const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const login_domain = @import("../domain/login.zig");
const LoginResult = login_domain.LoginResult;

const user_repository = @import("../repositories/user.zig");

pub fn login(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    email: []const u8,
    password: []const u8,
) !LoginResult {
    const hash_with_id = try user_repository.findPasswordHashByEmail(
        db,
        allocator,
        email,
    ) orelse return .failure;

    if (try login_domain.verifyPassword(
        io,
        allocator,
        hash_with_id.password_hash,
        password,
    )) {
        return .{ .success = hash_with_id.user_id };
    } else {
        return .failure;
    }
}
