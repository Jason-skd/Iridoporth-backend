pub const RaspiStatusResponse = struct { ok: bool = true, data: struct {
    available: bool,
    name: ?[]const u8 = null,
    cpu_temperature: ?f32 = null,
    cpu_usage: ?f32 = null,
    memory_usage: ?f32 = null,
} };
