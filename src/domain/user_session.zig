pub const UserSession = @This();

id: i64,
user_id: i64,
method: Method,
token_hash: []const u8,
created_at: i64,
expires_at: i64,
last_used_at: i64,
revoked_at: ?i64,

pub const Method = enum {
    anonymous_cookie,
    password_login,

    const BaseType = []const u8;
};
