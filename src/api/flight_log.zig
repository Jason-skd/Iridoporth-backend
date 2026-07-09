pub const FlightLogEntryDTO = struct {
    id: i64,
    content: []const u8,
    response: ?[]const u8,
    responded_at: ?i64,
    callsign: []const u8,
    created_at: i64,
    created_by_this_user: bool,
    likes: i64,
    liked_by_this_user: bool,
};

pub const FlightLogListResponse = struct { ok: bool, data: struct {
    entries: []const FlightLogEntryDTO,
} };

pub const FlightLogPostRequest = struct {
    content: []const u8,
};

pub const FlightLogPostResponse = struct { ok: bool, data: struct {
    id: i64,
    created_at: i64,
} };
