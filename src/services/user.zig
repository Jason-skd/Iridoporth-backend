const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_repository = @import("../repositories/user.zig");

const login_domain = @import("../domain/login.zig");

pub const AuthorizationError = error{
    UserNotFound,
};

pub fn isAdmin(allocator: Allocator, db: *Db, user_id: i64) !bool {
    const user = try user_repository.findUserById(
        allocator,
        db,
        user_id,
    ) orelse return AuthorizationError.UserNotFound;
    return user.role == .admin;
}

pub const PasswordError = error{
    InvalidCurrent,
    UserNotFound,
};

pub fn changePassword(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    user_id: i64,
    current_password: []const u8,
    new_password: []const u8,
) !void {
    const stored_hash = try user_repository.findPasswordHashByUserId(
        db,
        allocator,
        user_id,
    ) orelse return PasswordError.InvalidCurrent;

    const current_ok = try login_domain.verifyPassword(
        io,
        allocator,
        stored_hash,
        current_password,
    );
    if (!current_ok) return PasswordError.InvalidCurrent;

    const new_hash = try login_domain.hashPassword(
        io,
        allocator,
        new_password,
    );

    const updated = try user_repository.setPasswordHash(
        io,
        db,
        user_id,
        new_hash,
    );
    if (!updated) return PasswordError.UserNotFound;
}
