const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_domain = @import("../domain/user.zig");
const User = user_domain.User;
const UserDraft = user_domain.UserDraft;

pub fn createAnonymousUser(io: std.Io, allocator: Allocator, db: *Db) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const user_draft = user_domain.UserDraft.init(.anonymous, .user, created_at);
    const user = try insertUser(allocator, db, user_draft);

    return user;
}

pub fn createAccountUser(io: std.Io, allocator: Allocator, db: *Db, email: []const u8, name: []const u8) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const user_draft = user_domain.UserDraft.init(.account, .user, created_at, .{ .email = email, .name = name });
    const user = try insertUser(allocator, db, user_draft);

    return user;
}

pub fn createAdmin(io: std.Io, allocator: Allocator, db: *Db, email: []const u8, name: []const u8) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const user_draft = user_domain.UserDraft.init(.account, .admin, created_at, .{ .email = email, .name = name });
    const user = try insertUser(allocator, db, user_draft);

    return user;
}

pub fn findUserById(allocator: Allocator, db: *Db, user_id: i64) !?User {
    const query = (
        \\SELECT user_id, kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name
        \\FROM users
        \\WHERE user_id = :user_id{i64} AND disabled_at IS NULL 
    );

    return findUser(allocator, db, query, .{ .user_id = user_id });
}

pub fn findUserByEmail(allocator: Allocator, db: *Db, email: []const u8) !?User {
    const query = (
        \\SELECT user_id, kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name
        \\FROM users
        \\WHERE email = :email{[]const u8} AND (disabled_at IS NULL)
    );

    return findUser(allocator, db, query, .{ .email = email });
}

pub fn setPasswordHash(io: std.Io, db: *Db, user_id: i64, password_hash: []const u8) !void {
    const now = std.Io.Timestamp.now(io, .real);
    const changed_at = now.toSeconds();

    const query = (
        \\INSERT INTO user_password_credentials (user_id, password_hash, changed_at)
        \\SELECT user_id, :password_hash{[]const u8}, :changed_at{i64}
        \\FROM users
        \\WHERE user_id = :user_id{i64}
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

    return try stmt.oneAlloc([]const u8, allocator, .{}, .{ .user_id = user_id });
}

pub const PasswordHashWithUserId = struct {
    password_hash: []const u8,
    user_id: i64,
};

pub fn findPasswordHashByEmail(db: *Db, allocator: Allocator, email: []const u8) !?PasswordHashWithUserId {
    const query = (
        \\SELECT upc.password_hash, upc.user_id
        \\FROM user_password_credentials AS upc
        \\JOIN users AS u ON upc.user_id = u.user_id
        \\WHERE u.email = :email{[]const u8}
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    return try stmt.oneAlloc(PasswordHashWithUserId, allocator, .{}, .{ .email = email });
}

fn insertUser(allocator: Allocator, db: *Db, user_draft: UserDraft) !User {
    const query = (
        \\INSERT INTO users (kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name)
        \\VALUES (:kind{[]const u8}, :role{user_domain.Role}, :created_at{i64}, :updated_at{i64}, :last_seen_at{i64}, :disabled_at{?i64}, :email{?[]const u8}, :name{?[]const u8})
        \\RETURNING user_id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct { user_id: i64 };

    const row = (try stmt.oneAlloc(Row, allocator, .{}, .{
        .kind = @tagName(user_draft.kind),
        .role = user_draft.role,
        .created_at = user_draft.created_at,
        .updated_at = user_draft.updated_at,
        .last_seen_at = user_draft.last_seen_at,
        .disabled_at = user_draft.disabled_at,
        .email = switch (user_draft.kind) {
            .anonymous => null,
            .account => |account| account.email,
        },
        .name = switch (user_draft.kind) {
            .anonymous => null,
            .account => |account| account.name,
        },
    })) orelse return error.InsertDidNotReturnRow;

    return .{
        .id = row.user_id,
        .kind = user_draft.kind,
        .role = user_draft.role,
        .created_at = user_draft.created_at,
        .updated_at = user_draft.updated_at,
        .last_seen_at = user_draft.last_seen_at,
        .disabled_at = user_draft.disabled_at,
    };
}

fn findUser(allocator: Allocator, db: *Db, comptime query: []const u8, values: anytype) !?User {
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
