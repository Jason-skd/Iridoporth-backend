pub const UserSession = struct {
    id: i64,
    user_id: i64,
    method: Method,
    token_hash: []const u8,
    created_at: i64,
    expires_at: i64,
    last_used_at: i64,
    revoked_at: ?i64,
};

pub const UserSessionDraft = struct {
    user_id: i64,
    method: Method,
    token_hash: []const u8,
    created_at: i64,
    expires_at: i64,
    last_used_at: i64,
    revoked_at: ?i64,

    pub fn init(user_id: i64, method: Method, token_hash: []const u8, now: i64, expires_at: i64) UserSessionDraft {
        return .{
            .user_id = user_id,
            .method = method,
            .token_hash = token_hash,
            .created_at = now,
            .expires_at = expires_at,
            .last_used_at = now,
            .revoked_at = null,
        };
    }
};

pub const Method = enum {
    anonymous_cookie,
    password_login,

    const BaseType = []const u8;
    const default = .anonymous_cookie;
};
