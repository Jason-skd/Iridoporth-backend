pub const LoginRequest = struct {
    email: []const u8,
    password: []const u8,
};

pub const LoginResponse = struct { ok: bool = true, data: struct {
    success: bool,
    session_token: ?[]const u8,
} };
