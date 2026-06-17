pub const User = @This();

id: i64,
kind: Kind,
role: Role,
created_at: i64,
updated_at: i64,
last_seen_at: i64,
disabled_at: ?i64,

pub const Kind = union(enum) {
    anonymous: void,
    account: struct {
        email: []const u8,
        name: []const u8,
    },
};

pub const Role = enum {
    admin,
    user,
};
