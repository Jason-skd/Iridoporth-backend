const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const raspi_status_endpoint = @import("endpoints/raspi_status.zig");
const RaspiStatusEndpoint = raspi_status_endpoint.RaspiStatusEndpoint;

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

    var app_context = Context.init(init.io);
    Context.setInstance(&app_context);
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
