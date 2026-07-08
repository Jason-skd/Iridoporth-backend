pub const FlightLogEntryDTO = struct {
    id: i64,
    content: []const u8,
    callsign: []const u8,
    created_at: i64,
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
