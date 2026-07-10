pub const User = struct {
    id: i64,
    kind: Kind,
    role: Role,
    created_at: i64,
    updated_at: i64,
    last_seen_at: i64, // TODO: not used yet!
    disabled_at: ?i64,
};

pub const UserDraft = struct {
    kind: Kind,
    role: Role,
    created_at: i64,
    updated_at: i64,
    last_seen_at: i64,
    disabled_at: ?i64,

    pub fn init(kind: Kind, role: Role, now: i64) UserDraft {
        return .{
            .kind = kind,
            .role = role,
            .created_at = now,
            .updated_at = now,
            .last_seen_at = now,
            .disabled_at = null,
        };
    }
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
            .anonymous => .anonymous,
            .account => blk: {
                if (email == null or name == null) {
                    break :blk error.InvalidAccountUserData;
                }
                break :blk .{ .account = .{
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
