pub const User = struct {
    id: i64,
    kind: Kind,
    role: Role,
    created_at: i64,
    updated_at: i64,
    last_seen_at: i64,
    disabled_at: ?i64,
};

pub const NewUser = struct {
    kind: Kind,
    role: Role,
    created_at: i64,
    updated_at: i64,
    last_seen_at: i64,
    disabled_at: ?i64,
};

pub const KindTag = enum {
    anonymous,
    account,

    pub const BaseType = []const u8;
    pub const default = .anonymous;
};

pub const Kind = union(KindTag) {
    anonymous: void,
    account: struct {
        email: []const u8,
        name: []const u8,
    },

    pub fn fromDb(tag: KindTag, email: ?[]const u8, name: ?[]const u8) !Kind {
        return switch (tag) {
            .anonymous => .{ .anonymous = {} },
            .account => {
                if (email == null or name == null) {
                    return error.InvalidAccountUserData;
                }
                .{ .account = .{
                    .email = email.?,
                    .name = name.?,
                } };
            },
        };
    }
};

pub const Role = enum {
    admin,
    user,

    pub const BaseType = []const u8;
    pub const default = .user;
};

pub fn newAnonymous(now: i64) NewUser {
    return .{
        .kind = .anonymous,
        .role = .user,
        .created_at = now,
        .updated_at = now,
        .last_seen_at = now,
        .disabled_at = null,
    };
}

pub fn newAccount(name: []const u8, email: []const u8, now: i64) NewUser {
    return .{
        .kind = .account{ .email = email, .name = name },
        .role = .user,
        .created_at = now,
        .updated_at = now,
        .last_seen_at = now,
        .disabled_at = null,
    };
}
