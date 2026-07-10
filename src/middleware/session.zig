const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const Context = @import("../context.zig");

const user_session_domain = @import("../domain/user_session.zig");
const SessionTokenRandomHex = user_session_domain.SessionTokenRandomHex;

const user_repository = @import("../repositories/user.zig");

const user_session_repository = @import("../repositories/user_session.zig");

const SessionContext = struct {
    user_id: i64,
    new_session_token: SessionTokenRandomHex,
};

pub fn requireUserIdOrCreateAnonymous(
    ctx: *Context,
    arena: Allocator,
    r: zap.Request,
) !i64 {
    const token_cookie: ?[]const u8 = (try r.getCookieStr(arena, "iridoporth_session"));

    var user_id: i64 = undefined;
    if (token_cookie == null) {
        const session_context = try createAnonymousSession(
            ctx.io,
            arena,
            &ctx.db,
        );
        try setSessionToken(session_context.new_session_token, r);
        user_id = session_context.user_id;
    } else {
        user_id = try findUserId(arena, &ctx.db, token_cookie.?);
    }

    return user_id;
}

pub fn getUserIdOrNull(ctx: *Context, arena: Allocator, r: zap.Request) !?i64 {
    const token: []const u8 = (try r.getCookieStr(
        arena,
        "iridoporth_session",
    )) orelse return null;
    const user_id = try findUserId(arena, &ctx.db, token);
    return user_id;
}

pub fn requireAdmin(ctx: *Context, arena: Allocator, r: zap.Request) !i64 {
    const token: []const u8 = (try r.getCookieStr(
        arena,
        "iridoporth_session",
    )) orelse return error.InvalidSessionToken;
    const user_id = try findUserId(arena, &ctx.db, token);

    const user = try (user_repository.findUserById(
        &ctx.db,
        arena,
        user_id,
    )) orelse return error.InvalidSessionToken;

    if (!user.is_admin) {
        return error.NotAdmin;
    }
    return user_id;
}

pub fn setSessionForAccount(
    ctx: *Context,
    arena: Allocator,
    r: zap.Request,
    user_id: i64,
) !void {
    const new_session_token = try createSession(
        ctx.io,
        arena,
        &ctx.db,
        user_id,
    );
    try setSessionToken(new_session_token, r);
}

fn createAnonymousSession(io: std.Io, allocator: Allocator, db: *Db) !SessionContext {
    const new_user = try user_repository.createAnonymousUser(
        io,
        allocator,
        db,
    );
    const user_id = new_user.id;

    const new_session_token = try createSession(
        io,
        allocator,
        db,
        user_id,
    );

    return .{
        .user_id = user_id,
        .new_session_token = new_session_token,
    };
}

fn createSession(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    user_id: i64,
) !SessionTokenRandomHex {
    const new_session_token = try user_session_domain.generateSessionToken(io);
    const token_hash = user_session_domain.hashSessionToken(new_session_token[0..]);

    const now = std.Io.Timestamp.now(io, .real);
    const expires_at = now.toSeconds() + (60 * 60 * 24 * 91); // 91 days from now
    _ = try user_session_repository.createSession(
        io,
        db,
        allocator,
        user_id,
        .anonymous_cookie,
        token_hash[0..],
        expires_at,
    );

    return new_session_token;
}

fn findUserId(allocator: Allocator, db: *Db, token: []const u8) !i64 {
    const token_hash = user_session_domain.hashSessionToken(token);

    const session = try (user_session_repository.findUserSessionByTokenHash(
        db,
        allocator,
        token_hash[0..],
    )) orelse return error.InvalidSessionToken;
    return session.user_id;
}

fn setSessionToken(new_token: SessionTokenRandomHex, r: zap.Request) !void {
    try r.setCookie(.{
        .name = "iridoporth_session",
        .value = new_token[0..],
        .path = "/",
        .max_age_s = 60 * 60 * 24 * 91, // 91 days, a season
        .http_only = true,
        .secure = false, // TODO: set to true in production
        .same_site = .Lax, // TODO: set to .Strict in production
    });
}
