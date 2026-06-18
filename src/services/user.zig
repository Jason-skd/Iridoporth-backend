const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const sqlite_adapter = @import("../db/sqlite");

const user_domain = @import("../domain/user.zig");
const User = user_domain.User;
const NewUser = user_domain.NewUser;

const UserSession = @import("../domain/user_session.zig").UserSession;

pub fn createAnonymousUser(io: std.Io, db: *Db, allocator: Allocator) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const new_user: NewUser = user_domain.newAnonymous(created_at);
    const user = try insertUser(db, allocator, new_user);

    return user;
}

pub fn createAccountUser(io: std.Io, db: *Db, allocator: Allocator, name: []const u8, email: []const u8) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const new_user: NewUser = user_domain.newAccount(name, email, created_at);
    const user = try insertUser(db, allocator, new_user);

    return user;
}

pub fn findUserById(db: *Db, allocator: Allocator, user_id: i64) !?User {
    const query = (
        \\SELECT id, kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name
        \\FROM users
        \\WHERE id = ? AND disabled_at IS NULL 
    );

    return findUser(db, allocator, query, .{ .user_id = user_id });
}

pub fn findUserByEmail(db: *Db, allocator: Allocator, email: []const u8) !?User {
    const query = (
        \\SELECT id, kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name
        \\FROM users
        \\WHERE email = ? AND (disabled_at IS NULL OR disabled_at > strftime('%s', 'now'))
    );

    return findUser(db, allocator, query, .{ .email = email });
}

pub fn setPasswordHash(io: std.Io, db: *Db, user_id: i64, password_hash: []const u8) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const changed_at = now.toSeconds();

    const query = (
        \\INSERT INTO user_password_credentials (user_id, password_hash, changed_at)
        \\SELECT id, :password_hash{[]const u8}, :changed_at{i64}
        \\FROM users
        \\WHERE id = :user_id{i64}
        \\  AND kind = 'account'
        \\  AND disabled_at IS NULL
        \\ON CONFLICT(user_id) DO UPDATE SET
        \\  password_hash = excluded.password_hash,
        \\  changed_at = excluded.changed_at
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .password_hash = password_hash,
        .changed_at = changed_at,
        .user_id = user_id,
    });

    if (db.rowsAffected() == 0) {
        return error.UserNotFoundOrNotAccount;
    }
}

pub fn findPasswordHashByUserId(db: *Db, allocator: Allocator, user_id: i64) !?[]const u8 {
    const query = (
        \\SELECT password_hash
        \\FROM user_password_credentials
        \\WHERE user_id = :user_id{i64}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    return try stmt.oneAlloc([]const u8, allocator, .{}, .{ .user_id = user_id }) orelse null;
}

fn insertUser(db: *Db, allocator: Allocator, new_user: NewUser) !User {
    const query = (
        \\INSERT INTO users (kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        \\RETURNING id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct { id: i64 };

    const row = (try stmt.oneAlloc(Row, allocator, .{}, .{
        .kind = @tagName(new_user.kind),
        .role = new_user.role,
        .created_at = new_user.created_at,
        .updated_at = new_user.updated_at,
        .last_seen_at = new_user.last_seen_at,
        .disabled_at = new_user.disabled_at orelse null,
        .email = switch (new_user.kind) {
            .anonymous => null,
            .account => |account| account.email,
        },
        .name = switch (new_user.kind) {
            .anonymous => null,
            .account => |account| account.name,
        },
    })) orelse return error.InsertDidNotReturnRow;

    return .{
        .id = row.id,
        .kind = new_user.kind,
        .role = new_user.role,
        .created_at = new_user.created_at,
        .updated_at = new_user.updated_at,
        .last_seen_at = new_user.last_seen_at,
        .disabled_at = new_user.disabled_at,
    };
}

fn findUser(db: *Db, allocator: Allocator, comptime query: []const u8, values: anytype) !?User {
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct {
        id: i64,
        kind: user_domain.KindTag,
        role: user_domain.Role,
        created_at: i64,
        updated_at: i64,
        last_seen_at: i64,
        disabled_at: ?i64,
        email: ?[]const u8,
        name: ?[]const u8,
    };

    const row = try stmt.oneAlloc(Row, allocator, .{}, values) orelse return null;

    const kind = try user_domain.Kind.fromDb(row.kind, row.email, row.name);

    return .{
        .id = row.id,
        .kind = kind,
        .role = row.role,
        .created_at = row.created_at,
        .updated_at = row.updated_at,
        .last_seen_at = row.last_seen_at,
        .disabled_at = row.disabled_at,
    };
}
