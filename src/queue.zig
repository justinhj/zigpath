const std = @import("std");
const maxInt = std.math.maxInt(usize);

const QueueError = error{
    OutOfMemory,
};

pub fn Queue(comptime Child: type) type {
    return struct {
        const This = @This();
        gpa: std.mem.Allocator,
        start: usize,
        end: usize,
        items: []Child,

        pub fn init(gpa: std.mem.Allocator, initialCapacity: usize) QueueError!This {
            const items = gpa.alloc(Child, initialCapacity) catch return QueueError.OutOfMemory;
            return This{
                .gpa = gpa,
                .start = maxInt,
                .end = maxInt,
                .items = items,
            };
        }
        pub fn capacity(this: *This) usize {
            return this.items.len;
        }
        pub fn deinit(this: *This) void {
            this.start = maxInt;
            this.end = maxInt;
            this.gpa.free(this.items);
        }
        pub fn enqueue(this: *This, value: Child) !void {
            if (this.start == maxInt) {
                this.start = 0;
                this.end = 0;
                this.items[this.start] = value;
            } else {
                const newEnd = (this.end + 1) % this.items.len;
                if (newEnd == this.start) {
                    const newCapacity = this.items.len * 2;
                    const newItems = this.gpa.alloc(Child, newCapacity) catch return QueueError.OutOfMemory;

                    var i: usize = 0;
                    var current = this.start;
                    while (current != this.end) {
                        newItems[i] = this.items[current];
                        current = (current + 1) % this.items.len;
                        i += 1;
                    }
                    newItems[i] = this.items[this.end];

                    this.gpa.free(this.items);

                    // Update the queue state
                    this.items = newItems;
                    this.start = 0;
                    this.end = i;

                    // Enqueue the new value
                    this.end = (this.end + 1) % this.items.len;
                    this.items[this.end] = value;
                } else {
                    this.end = newEnd;
                    this.items[this.end] = value;
                }
            }
            return {};
        }
        pub fn dequeue(this: *This) ?Child {
            if (this.start == maxInt) {
                return null;
            } else {
                const value = this.items[this.start];
                if (this.start == this.end) {
                    this.start = maxInt;
                    this.end = maxInt;
                } else {
                    this.start = (this.start + 1) % this.items.len;
                }
                return value;
            }
        }
    };
}

const testing = std.testing;

test "basic queue operations" {
    var int_queue = try Queue(i32).init(testing.allocator, 10);
    defer int_queue.deinit();

    try int_queue.enqueue(25);
    try int_queue.enqueue(50);
    try int_queue.enqueue(75);
    try int_queue.enqueue(100);

    try testing.expectEqual(25, int_queue.dequeue());
    try testing.expectEqual(50, int_queue.dequeue());
    try testing.expectEqual(75, int_queue.dequeue());
    try testing.expectEqual(100, int_queue.dequeue());
    try testing.expectEqual(null, int_queue.dequeue());
}

test "empty queue handling" {
    var int_queue = try Queue([]const u8).init(testing.allocator, 10);
    defer int_queue.deinit();

    try testing.expectEqual(null, int_queue.dequeue());

    try int_queue.enqueue("a");
    try testing.expectEqualStrings("a", int_queue.dequeue().?);

    try testing.expectEqual(null, int_queue.dequeue());
}

test "Expanding capacity" {
    var int_queue = try Queue(f32).init(testing.allocator, 4);
    defer int_queue.deinit();

    try int_queue.enqueue(1.0);
    try int_queue.enqueue(1.0);
    try int_queue.enqueue(1.0);
    try int_queue.enqueue(1.0);
    try testing.expectEqual(4, int_queue.capacity());

    try int_queue.enqueue(1.0);
    try testing.expectEqual(8, int_queue.capacity());
    try int_queue.enqueue(1.0);
    try int_queue.enqueue(1.0);
    try int_queue.enqueue(1.0);

    try int_queue.enqueue(1.0);
    try testing.expectEqual(16, int_queue.capacity());

    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();

    try testing.expectEqual(16, int_queue.capacity());

    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();
    _ = int_queue.dequeue();

    try testing.expectEqual(16, int_queue.capacity());
}
