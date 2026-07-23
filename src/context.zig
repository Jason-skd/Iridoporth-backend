const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const zap = @import("zap");

const sqlite = @import("sqlite");
const Db = sqlite.Db;

const raspi_status_domain = @import("domain/raspi_status.zig");
const Raspi = raspi_status_domain.Raspi;

const raspi_status_service = @import("services/raspi_status.zig");

const sqlite_adapter = @import("db/sqlite.zig");

const api_error = @import("http/api_error.zig");

const response_http = @import("http/response.zig");

pub const Context = @This();

pub fn init(io: std.Io, allocator: Allocator, db_path: [:0]const u8) !Context {
    var raspi = raspi_status_service.init(io, allocator);
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

pub fn unhandledRequest(_: *Context, _: Allocator, r: zap.Request) !void {
    response_http.sendStaticJson(r, .not_found, "{\"ok\": false}");
}

pub fn unhandledError(_: *Context, r: zap.Request, err: anyerror) void {
    std.debug.print(
        "Unhandled HTTP error: method={s} path={s} error={}\n",
        .{
            r.method orelse "<unknown>",
            r.path orelse "<unknown>",
            err,
        },
    );

    if (api_error.classify(err)) |public_error| {
        response_http.sendPublicError(r, public_error);
    } else {
        response_http.sendPublicError(r, .{
            .status = .internal_server_error,
            .code = "internal_error",
        });
    }
}
