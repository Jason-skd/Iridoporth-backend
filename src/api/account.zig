pub const ChangePasswordRequest = struct {
    current_password: []const u8,
    new_password: []const u8,
};

pub const ChangePasswordResponse = struct {
    ok: bool = true,
    data: struct {},
};
