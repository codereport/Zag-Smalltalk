const std = @import("std");
const builtin = @import("builtin");
var next_thread_number : u64 = 0;
const Object = @import("object.zig").Object;
const heap = @import("heap.zig");
test "sizes" {
    try std.testing.expectEqual(Thread.size,42);
}
pub const Thread = struct {
//    header: heap.Header,
    id : u64,
    nursery : heap.Arena,
//    tean1 : heap.Arena,
//    teen2 : heap.Arena,
    next: ?*Thread,
    const psm1 = std.mem.page_size-1;
    const size = (@sizeOf(Thread)+3000*@sizeOf(Object)+psm1)&-std.mem.page_size;
    const nursery_size = (size-@sizeOf(Thread))/6;
    const teen_size = nursery_size*5/2; 
    const Self = @This();
    pub fn init() !Self {
        defer next_thread_number += 1;
        return Self {
            .id = next_thread_number,
            .nursery = try heap.NurseryArena.init(),
            .next = null,
        };
    }
    pub fn initForTest() !Self {
        if (builtin.is_test) {
            return Self {
                .id = 0,
                .nursery = try heap.TestArena.init(),
                .next = null,
            };
        }
        else unreachable;
    }
    pub fn deinit(self : *Self) void {
        self.heap.deinit();
        self.* = undefined;
    }
    pub inline fn getArena(self: *Self) *heap.Arena {
        return &self.nursery;
    }
};
