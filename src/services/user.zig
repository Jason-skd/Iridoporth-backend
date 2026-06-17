const std = @import("std");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const sqlite_adapter = @import("../db/sqlite");

const user_domain = @import("../domain/user.zig");
const User = user_domain.User;
const NewUser = user_domain.NewUser;

const UserSession = @import("../domain/user_session.zig").UserSession;

pub fn createAnonymousUser(io: std.Io, db: *Db) !User {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const new_user: NewUser = user_domain.newAnonymous(created_at);
    const user = try insertUser(db, new_user);

    return user;
}

fn insertUser(db: *Db, new_user: NewUser) !User {
    const query = (
        \\INSERT INTO users (kind, role, created_at, updated_at, last_seen_at, disabled_at, email, name)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        \\RETURNING id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct { id: i64 };

    const row = (try stmt.one(Row, .{}, .{
        .kind = @tagName(new_user.kind),
        .role = new_user.role,
        .created_at = new_user.created_at,
        .updated_at = new_user.updated_at,
        .last_seen_at = new_user.last_seen_at,
        .disabled_at = new_user.disabled_at orelse null,
        .email = switch (new_user.kind) {
            .anonymous => null,
            .account => new_user.kind.account.email,
        },
        .name = switch (new_user.kind) {
            .anonymous => null,
            .account => new_user.kind.account.name,
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
