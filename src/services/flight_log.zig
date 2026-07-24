const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const user_repository = @import("../repositories/user.zig");

const flight_log_repository = @import("../repositories/flight_log.zig");

const flight_log_api = @import("../api/flight_log.zig");
const FlightLogEntryDTO = flight_log_api.FlightLogEntryDTO;
const FlightLogAdminEntryDTO = flight_log_api.FlightLogAdminEntryDTO;

pub fn listAll(allocator: Allocator, db: *Db, viewer_user_id: ?i64) ![]FlightLogEntryDTO {
    const entries = try flight_log_repository.listAll(
        allocator,
        db,
        viewer_user_id,
    );

    var dtos = try allocator.alloc(FlightLogEntryDTO, entries.len);
    for (0.., entries) |i, entry| {
        dtos[i] = FlightLogEntryDTO{
            .id = entry.id,
            .content = entry.content,
            .response = switch (entry.response) {
                .None => null,
                .Response => |response| response.content,
            },
            .responded_at = switch (entry.response) {
                .None => null,
                .Response => |response| response.responded_at,
            },
            .callsign = entry.callsign,
            .created_at = entry.created_at,
            .created_by_this_user = entry.created_by_this_user,
            .likes = entry.likes,
            .liked_by_this_user = entry.liked_by_this_user,
        };
    }

    return dtos;
}

pub fn listAllForAdmin(allocator: Allocator, db: *Db, viewer_user_id: ?i64) ![]FlightLogAdminEntryDTO {
    const entries = try flight_log_repository.listAllForAdmin(
        allocator,
        db,
        viewer_user_id,
    );

    var dtos = try allocator.alloc(FlightLogAdminEntryDTO, entries.len);
    for (0.., entries) |i, entry| {
        dtos[i] = FlightLogAdminEntryDTO{
            .id = entry.id,
            .content = entry.content,
            .response = switch (entry.response) {
                .None => null,
                .Response => |response| response.content,
            },
            .responded_at = switch (entry.response) {
                .None => null,
                .Response => |response| response.responded_at,
            },
            .callsign = entry.callsign,
            .created_at = entry.created_at,
            .created_by_this_user = entry.created_by_this_user,
            .likes = entry.likes,
            .liked_by_this_user = entry.liked_by_this_user,
            .deleted_at = entry.deleted_at,
            .hidden_at = entry.hidden_at,
        };
    }

    return dtos;
}
