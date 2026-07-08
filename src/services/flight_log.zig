const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_repository = @import("../repositories/user.zig");

const flight_log_repository = @import("../repositories/flight_log.zig");

const flight_log_api = @import("../api/flight_log.zig");
const FlightLogEntryDTO = flight_log_api.FlightLogEntryDTO;

pub fn listAll(allocator: Allocator, db: *Db) ![]FlightLogEntryDTO {
    const entries = try flight_log_repository.listAll(allocator, db);

    var dtos = try allocator.alloc(FlightLogEntryDTO, entries.len);
    for (0.., entries) |i, entry| {
        const user = try user_repository.findUserById(allocator, db, entry.creator_user_id) orelse return error.UserNotFound;
        const callsign = switch (user.kind) {
            .anonymous => "Anonymous",
            .account => |account| account.name,
        };
        dtos[i] = FlightLogEntryDTO{
            .id = entry.id,
            .content = entry.content,
            .callsign = callsign,
            .created_at = entry.created_at,
        };
    }

    return dtos;
}
