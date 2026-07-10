const std = @import("std");
const Allocator = std.mem.Allocator;

const zap = @import("zap");

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
