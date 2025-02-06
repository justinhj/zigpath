const std = @import("std");
const maxInt = std.math.maxInt(usize);
const ArrayList = std.ArrayList;

pub fn Queue(comptime Child: type) type {
    return struct {
        const This = @This();
        gpa: std.mem.Allocator,
        start: usize,
        end: usize,
        items: []Child,

        pub fn init(gpa: std.mem.Allocator, capacity: usize) !This {
            const items = try gpa.alloc(Child, capacity);
            return This{
                .gpa = gpa,
                .start = maxInt,
                .end = maxInt,
                .items = items,
            };
        }
        pub fn deinit(this: *This) void {
            this.start = maxInt;
            this.end = maxInt;
            this.gpa.free(this.items);
        }
        pub fn enqueue(this: *This, value: Child) !void {
            _ = this;
            _ = value;
            return {};
        }
        pub fn dequeue(this: *This) ?Child {
            _ = this;
            return null;
        }
    };
}

const testing = std.testing;

test "queue" {
    var int_queue = try Queue(i32).init(testing.allocator, 7);

    try int_queue.enqueue(25);
    try int_queue.enqueue(50);
    try int_queue.enqueue(75);
    try int_queue.enqueue(100);

    try testing.expectEqual(25, int_queue.dequeue());
    try testing.expectEqual(50, int_queue.dequeue());
    try testing.expectEqual(75, int_queue.dequeue());
    try testing.expectEqual(100, int_queue.dequeue());
    try testing.expectEqual(null, int_queue.dequeue());

    try int_queue.enqueue(5);
    try testing.expectEqual(5, int_queue.dequeue());
    try testing.expectEqual(null, int_queue.dequeue());
}
