const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const zap = @import("zap");

const raspi_service = @import("services/raspi.zig");
const Raspi = raspi_service.Raspi;

const Context = @This();

var _instance: *Context = undefined;

pub fn init(io: std.Io) Context {
    return .{
        .raspi = raspi_service.init(io),
    };
}

pub fn deinit(self: *Context) void {
    _ = self;
    _instance = undefined;
}

pub fn setInstance(ctx: *Context) void {
    _instance = ctx;
}

raspi: Raspi,

pub fn unhandledRequest(_: *Context, _: Allocator, r: zap.Request) anyerror!void {
    r.setStatus(.not_found);
    try r.sendBody("Not Found");
}

pub fn unhandledError(_: *Context, r: zap.Request, err: anyerror) void {
    std.debug.print("Unhandled error: {}\n", .{err});
    r.setStatus(.internal_server_error);
    r.sendBody("Internal Server Error") catch {};
}
