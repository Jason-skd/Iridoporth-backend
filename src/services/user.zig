const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_repository = @import("../repositories/user.zig");

const login_domain = @import("../domain/login.zig");

const sqlite_adapter = @import("../db/sqlite.zig");

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

pub fn ensureAdminAccount(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    email: []const u8,
    name: []const u8,
    password: []const u8,
) !void {
    // Already provisioned — leave it (and its password) untouched.
    if (try user_repository.findUserByEmail(allocator, db, email) != null) return;

    const admin = try user_repository.createAdmin(io, allocator, db, email, name);
    const password_hash = try login_domain.hashPassword(io, allocator, password);
    _ = try user_repository.setPasswordHash(io, db, admin.id, password_hash);
}

test "ensureAdminAccount creates an admin on first call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    try ensureAdminAccount(
        std.testing.io,
        arena.allocator(),
        &db,
        "admin@example.com",
        "Admin",
        "Admin0001",
    );

    const admin = try user_repository.findUserByEmail(
        arena.allocator(),
        &db,
        "admin@example.com",
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expect(admin.role == .admin);

    const hash = try user_repository.findPasswordHashByUserId(
        &db,
        arena.allocator(),
        admin.id,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expect(hash.len > 0);
}

test "ensureAdminAccount is idempotent and preserves password" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var db = try sqlite_adapter.openMigratedTestDb();
    defer db.deinit();

    const allocator = arena.allocator();

    try ensureAdminAccount(
        std.testing.io,
        allocator,
        &db,
        "admin@example.com",
        "Admin",
        "Admin0001",
    );

    const admin = try user_repository.findUserByEmail(
        allocator,
        &db,
        "admin@example.com",
    ) orelse return error.TestUnexpectedResult;

    const first_hash = try user_repository.findPasswordHashByUserId(
        &db,
        allocator,
        admin.id,
    ) orelse return error.TestUnexpectedResult;

    // Second call must not create a duplicate or overwrite the password.
    try ensureAdminAccount(
        std.testing.io,
        allocator,
        &db,
        "admin@example.com",
        "Admin",
        "DifferentPassword123",
    );

    const second_hash = try user_repository.findPasswordHashByUserId(
        &db,
        allocator,
        admin.id,
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expectEqualStrings(first_hash, second_hash);
}
