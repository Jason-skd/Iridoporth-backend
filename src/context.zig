const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const raspi_service = @import("services/raspi.zig");
const Raspi = raspi_service.Raspi;

const sqlite_adapter = @import("db/sqlite.zig");

pub const Context = @This();

pub fn init(io: std.Io, allocator: Allocator, db_path: [:0]const u8) !Context {
    var raspi = raspi_service.init(io, allocator);
    errdefer raspi.deinit(allocator);

    const db = try sqlite_adapter.init(db_path);

    return .{
        .io = io,
        .allocator = allocator,
        .raspi = raspi,
        .db = db,
    };
}

pub fn deinit(self: *Context) void {
    self.raspi.deinit(self.allocator);
    self.db.deinit();
}

io: std.Io,
allocator: Allocator,
raspi: Raspi,
db: Db,

pub fn unhandledRequest(_: *Context, _: Allocator, r: zap.Request) anyerror!void {
    r.setStatus(.not_found);
    try r.sendBody("Not Found");
}

pub fn unhandledError(_: *Context, r: zap.Request, err: anyerror) void {
    std.debug.print("Unhandled error: {}\n", .{err});
    r.setStatus(.internal_server_error);
    r.sendBody("Internal Server Error") catch {};
}
