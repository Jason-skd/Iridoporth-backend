pub const FlightLogEntry = struct {
    id: i64,
    content: []const u8,
    creator_user_id: i64,
    created_at: i64,
};
