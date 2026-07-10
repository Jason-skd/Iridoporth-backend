const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Raspi = union(enum) {
    unavailable: void,
    available: struct { name: []u8, status: RaspiStatus },

    pub fn deinit(self: *Raspi, allocator: Allocator) void {
        switch (self.*) {
            .unavailable => {},
            .available => |available| {
                allocator.free(available.name);
            },
        }

        self.* = .unavailable;
    }
};

pub const RaspiStatus = struct {
    cpu_temperature: std.atomic.Value(f32),
    cpu_usage: std.atomic.Value(f32),
    memory_usage: std.atomic.Value(f32),
};
