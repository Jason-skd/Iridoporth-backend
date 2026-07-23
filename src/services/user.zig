const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_repository = @import("../repositories/user.zig");

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
