const std = @import("std");
const Allocator = std.mem.Allocator;

const api_error = @import("api_error.zig");

const zap = @import("zap");

pub const ErrorResponse = struct {
    ok: bool = false,
    err: struct {
        code: []const u8,
    },
};

pub fn stringifyAndSendResponse(
    comptime T: type,
    arena: Allocator,
    r: zap.Request,
    response: T,
) !void {
    const body = try std.json.Stringify.valueAlloc(
        arena,
        response,
        .{},
    );
    try r.sendBody(body);
}

pub fn sendPublicError(
    r: zap.Request,
    public_error: api_error.PublicError,
) void {
    const response = ErrorResponse{ .err = .{
        .code = public_error.code,
    } };

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    std.json.Stringify.value(response, .{}, &writer) catch {
        r.setStatus(.internal_server_error);
        r.sendBody("{\"ok\": false}") catch {};
        return;
    };

    sendStaticJson(r, public_error.status, writer.buffered());
}

pub fn sendStaticJson(
    r: zap.Request,
    status: std.http.Status,
    body: []const u8,
) void {
    r.setStatus(status);
    r.setHeader("Content-Type", "application/json; charset=utf-8") catch {};
    r.sendBody(body) catch {};
}
