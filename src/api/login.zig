const LoginRequest = struct {
    email: []const u8,
    password: []const u8,
};

const LoginResponse = struct {
    ok: bool,
    data: struct {
        success: bool,
        session_token: ?[]const u8,
    },
};
