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

pub const FlightLogListResponse = struct { ok: bool = true, data: struct {
    entries: []const FlightLogEntryDTO,
} };

pub const FlightLogAdminEntryDTO = struct {
    id: i64,
    content: []const u8,
    response: ?[]const u8,
    responded_at: ?i64,
    callsign: []const u8,
    created_at: i64,
    created_by_this_user: bool,
    likes: i64,
    liked_by_this_user: bool,
    deleted_at: ?i64,
    hidden_at: ?i64,
};

pub const FlightLogAdminListResponse = struct { ok: bool = true, data: struct {
    entries: []const FlightLogAdminEntryDTO,
} };

pub const FlightLogPostRequest = struct {
    content: []const u8,
};

pub const FlightLogPostResponse = struct { ok: bool = true, data: struct {
    id: i64,
    created_at: i64,
} };

pub const FlightLogActionResponse = struct { ok: bool = true, data: struct {} };

pub const FlightLogPatchRequest = struct {
    is_deleted: ?bool = null,
    is_hidden: ?bool = null,
    response: ?[]const u8 = null,
    clear_response: ?bool = null,
};
