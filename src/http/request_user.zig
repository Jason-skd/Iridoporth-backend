const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const Context = @import("../context.zig");

const user_session_domain = @import("../domain/user_session.zig");
const SessionTokenRandomHex = user_session_domain.SessionTokenRandomHex;

const user_session_service = @import("../services/user_session.zig");

const user_service = @import("../services/user.zig");

pub fn requireUserIdOrCreateAnonymous(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
) !i64 {
    const token_cookie: ?[]const u8 = (try r.getCookieStr(allocator, "session_token"));

    var user_id: i64 = undefined;
    if (token_cookie == null) {
        const session_context = try user_session_service.createAnonymousSession(
            io,
            allocator,
            db,
        );
        try setSessionToken(session_context.new_session_token, r);
        user_id = session_context.user_id;
    } else {
        user_id = try user_session_service.findUserId(
            allocator,
            db,
            token_cookie.?,
        );
    }

    return user_id;
}

pub fn getUserIdOrNull(allocator: Allocator, db: *Db, r: zap.Request) !?i64 {
    const token: []const u8 = (try r.getCookieStr(
        allocator,
        "session_token",
    )) orelse return null;
    const user_id = try user_session_service.findUserId(
        allocator,
        db,
        token,
    );

    return user_id;
}

pub fn requireAdmin(allocator: Allocator, db: *Db, r: zap.Request) !i64 {
    const token: []const u8 = (try r.getCookieStr(
        allocator,
        "session_token",
    )) orelse return error.InvalidSessionToken;
    const user_id = try user_session_service.findUserId(
        allocator,
        db,
        token,
    );

    const is_admin = try user_service.isAdmin(
        allocator,
        db,
        user_id,
    );
    if (!is_admin) {
        return error.NotAdmin;
    }
    return user_id;
}

pub fn setSessionForAccount(
    io: std.Io,
    allocator: Allocator,
    db: *Db,
    r: zap.Request,
    user_id: i64,
) !void {
    const new_session_token = try user_session_service.createSession(
        io,
        allocator,
        db,
        user_id,
    );
    try setSessionToken(new_session_token, r);
}

fn setSessionToken(new_token: SessionTokenRandomHex, r: zap.Request) !void {
    try r.setCookie(.{
        .name = "session_token",
        .value = new_token[0..],
        .path = "/",
        .max_age_s = 60 * 60 * 24 * 91, // 91 days, a season
        .http_only = true,
        .secure = false, // TODO: set to true in production
        .same_site = .Lax, // TODO: set to .Strict in production
    });
}
