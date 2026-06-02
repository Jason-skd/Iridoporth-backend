const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const RaspiStatusEndpoint = @import("endpoints/raspi_status.zig");

const raspi_service = @import("services/raspi.zig");

const Context = @import("context.zig");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{
        .thread_safe = true,
    }) = .init;
    defer _ = assert(gpa.deinit() == .ok);
    const gpa_allocator = gpa.allocator();

    const public_folder = init.environ_map.get("IRIDOPORTH_PUBLIC_DIR");
    const port_text = init.environ_map.get("IRIDOPORTH_PORT") orelse "3000";
    const port = std.fmt.parseInt(usize, port_text, 10) catch 3000;

    const db_path = init.environ_map.get("IRIDOPORTH_DB_PATH") orelse "./data/iridoporth.db";
    const db_path_sentinel = try gpa_allocator.dupeSentinel(u8, db_path, 0);
    errdefer gpa_allocator.free(db_path_sentinel);

    var app_context = try Context.init(init.io, db_path_sentinel);
    gpa_allocator.free(db_path_sentinel);
    defer app_context.deinit();

    const sampler_thread = try std.Thread.spawn(.{}, raspi_service.statusSampler, .{
        &app_context,
        init.io,
    });
    sampler_thread.detach();

    const App = zap.App.Create(Context);
    try App.init(gpa_allocator, &app_context, .{
        .default_error_strategy = .log_to_response,
    });
    defer App.deinit();

    var raspiStatusEndpoint = RaspiStatusEndpoint{};
    try App.register(&raspiStatusEndpoint);

    try App.listen(.{
        .interface = "0.0.0.0",
        .port = port,
        .public_folder = public_folder,
    });

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
