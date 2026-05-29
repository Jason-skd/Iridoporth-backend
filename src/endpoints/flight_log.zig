const std = @import("std");
const zap = @import("zap");

// Also used by post request
const FlightLogEntry = struct {
    content: []const u8,
    callsign: ?[]const u8,
};

const FlightLogGetResponse = struct { ok: bool, data: struct {
    entries: []const FlightLogEntry,
} };
