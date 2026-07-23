const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const sqlite_adapter = @import("../db/sqlite.zig");

const user_session_domain = @import("../domain/user_session.zig");
const UserSession = user_session_domain.UserSession;
const UserSessionDraft = user_session_domain.UserSessionDraft;

pub fn createSession(
    io: std.Io,
    db: *Db,
    allocator: Allocator,
    user_id: i64,
    method: user_session_domain.Method,
    token_hash: []const u8,
    expires_at: i64,
) !UserSession {
    const now = std.Io.Timestamp.now(io, .real);
    const created_at = now.toSeconds();

    const session_draft = UserSessionDraft.init(
        user_id,
        method,
        token_hash,
        created_at,
        expires_at,
    );
    const session = try insertUserSession(
        db,
        allocator,
        session_draft,
    );

    return session;
}

pub fn findUserSessionByTokenHash(
    db: *Db,
    allocator: Allocator,
    token_hash: []const u8,
) !?UserSession {
    const query = (
        \\SELECT session_id, user_id, method, created_at, expires_at, last_used_at, revoked_at
        \\FROM user_sessions
        \\WHERE token_hash = :token_hash{[]const u8}
        \\  AND revoked_at IS NULL
        \\  AND expires_at > strftime('%s', 'now')
    );

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    return try stmt.oneAlloc(UserSession, allocator, .{}, .{ .token_hash = token_hash });
}

fn insertUserSession(
    db: *Db,
    allocator: Allocator,
    session_draft: UserSessionDraft,
) !UserSession {
    const query = (
        \\INSERT INTO user_sessions (user_id, method, token_hash, created_at, expires_at, last_used_at, revoked_at)
        \\VALUES (:user_id{i64}, :method{[]const u8}, :token_hash{[]const u8}, :created_at{i64}, :expires_at{i64}, :last_used_at{i64}, :revoked_at{?i64})
        \\RETURNING session_id
    );
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const Row = struct { session_id: i64 };

    const row = (try stmt.oneAlloc(Row, allocator, .{}, .{
        .user_id = session_draft.user_id,
        .method = @tagName(session_draft.method),
        .token_hash = session_draft.token_hash,
        .created_at = session_draft.created_at,
        .expires_at = session_draft.expires_at,
        .last_used_at = session_draft.last_used_at,
        .revoked_at = session_draft.revoked_at,
    })) orelse return sqlite_adapter.InsertReturningError.InsertDidNotReturnRow;

    return .{
        .id = row.session_id,
        .user_id = session_draft.user_id,
        .method = session_draft.method,
        .created_at = session_draft.created_at,
        .expires_at = session_draft.expires_at,
        .last_used_at = session_draft.last_used_at,
        .revoked_at = session_draft.revoked_at,
    };
}
