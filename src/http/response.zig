const std = @import("std");
const Allocator = std.mem.Allocator;

const api_error = @import("api_error.zig");

const zap = @import("zap");

pub const ErrorResponse = struct {
    ok: bool = false,
    @"error": struct {
        code: []const u8,
    },
};

pub fn stringifyAndSendResponse(
    comptime T: type,
    arena: Allocator,
    r: zap.Request,
    status: std.http.Status,
    response: T,
) !void {
    const body = try std.json.Stringify.valueAlloc(
        arena,
        response,
        .{},
    );
    try sendStaticJson(r, status, body);
}

pub fn sendPublicError(
    r: zap.Request,
    public_error: api_error.PublicError,
) !void {
    const response = ErrorResponse{ .@"error" = .{
        .code = public_error.code,
    } };

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.json.Stringify.value(
        response,
        .{},
        &writer,
    );

    try sendStaticJson(r, public_error.status, writer.buffered());
}

fn sendStaticJson(
    r: zap.Request,
    status: std.http.Status,
    body: []const u8,
) !void {
    r.setStatusNumeric(@intFromEnum(status));
    try r.setHeader("Content-Type", "application/json; charset=utf-8");
    try r.sendBody(body);
}
