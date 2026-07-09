// not used yet
pub const FlightLogEntry = struct {
    id: i64,
    content: []const u8,
    response: FlightLogResponse,
    creator_user_id: i64,
    created_at: i64,
    deleted_at: ?i64, // user could delete the entry
    hidden_at: ?i64, // admin could hide the entry
};

pub const FlightLogListItem = struct {
    id: i64,
    content: []const u8,
    response: FlightLogResponse,
    callsign: []const u8,
    created_at: i64,
    created_by_this_user: bool,
    likes: i64,
    liked_by_this_user: bool,
};

pub const FlightLogResponseTag = enum {
    None,
    Response,

    pub const BaseType = []const u8;
    pub const default = .None;
};

pub const FlightLogResponse = union(FlightLogResponseTag) {
    None: void,
    Response: struct {
        content: []const u8,
        responded_at: i64,
    },

    pub fn fromDb(content: ?[]const u8, responded_at: ?i64) FlightLogResponse {
        if (content == null or responded_at == null) {
            return .None;
        } else {
            return .{
                .Response = .{
                    .content = content.?,
                    .responded_at = responded_at.?,
                },
            };
        }
    }
};
