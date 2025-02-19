const std = @import("std");
const ArrayList = std.ArrayList;

pub fn BinaryHeap(comptime Child: type) type {
    return struct {
        const This = @This();

        items: ArrayList(Child),
        lessThan: *const fn (a: Child, b: Child) bool,

        const Self = @This();

        // Initialize the binary heap
        pub fn initCapacity(allocator: std.mem.Allocator, initialCapacity: usize, lessThanFn: *const fn (Child, Child) bool) !Self {
            const items = try ArrayList(Child).initCapacity(allocator, initialCapacity);
            return Self{
                .items = items,
                .lessThan = lessThanFn,
            };
        }

        // Deinitialize the binary heap
        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        // Get the index of the parent node
        fn parentIndex(index: usize) usize {
            return (index - 1) / 2;
        }

        // Get the index of the left child node
        fn leftChildIndex(index: usize) usize {
            return 2 * index + 1;
        }

        // Get the index of the right child node
        fn rightChildIndex(index: usize) usize {
            return 2 * index + 2;
        }

        // Swap two elements in the heap
        fn swap(self: *Self, i: usize, j: usize) void {
            const temp = self.items.items[i];
            self.items.items[i] = self.items.items[j];
            self.items.items[j] = temp;
        }

        // Heapify up (used after insertion)
        fn heapifyUp(self: *Self, index: usize) void {
            var current = index;
            while (current > 0 and self.lessThan(self.items.items[current], self.items.items[parentIndex(current)])) {
                self.swap(current, parentIndex(current));
                current = parentIndex(current);
            }
        }

        // Heapify down (used after extraction)
        fn heapifyDown(self: *Self, index: usize) void {
            var current = index;
            while (true) {
                const left = leftChildIndex(current);
                const right = rightChildIndex(current);
                var smallest = current;

                if (left < self.items.items.len and self.lessThan(self.items.items[left], self.items.items[smallest])) {
                    smallest = left;
                }

                if (right < self.items.items.len and self.lessThan(self.items.items[right], self.items.items[smallest])) {
                    smallest = right;
                }

                if (smallest == current) break;

                self.swap(current, smallest);
                current = smallest;
            }
        }

        // Insert a new element into the heap
        pub fn insert(self: *Self, value: Child) !void {
            try self.items.append(value);
            self.heapifyUp(self.items.items.len - 1);
        }

        // Extract the minimum element from the heap
        pub fn extractMin(self: *Self) ?Child {
            if (self.items.items.len == 0) return null;

            const min = self.items.items[0];
            const last = self.items.items.len - 1;
            self.items.items[0] = self.items.items[last];
            _ = self.items.pop();
            self.heapifyDown(0);
            return min;
        }

        // Peek at the minimum element without removing it
        pub fn peekMin(self: *Self) ?Child {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }
    };
}

const testing = std.testing;

fn i32LessThan(a: i32, b: i32) bool {
    return a < b;
}

test "Basic" {
    var heap = try BinaryHeap(i32).init(testing.allocator, 10, i32LessThan);
    defer heap.deinit();

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);
    try heap.insert(12);
    try heap.insert(7);
    try heap.insert(8);
    try heap.insert(17);
    try heap.insert(5);
    try heap.insert(22);

    try testing.expect(heap.extractMin().? == 5);
    try testing.expect(heap.extractMin().? == 5);
    try testing.expect(heap.extractMin().? == 7);
    try testing.expect(heap.extractMin().? == 8);
    try testing.expect(heap.extractMin().? == 10);
    try testing.expect(heap.extractMin().? == 12);
    try testing.expect(heap.extractMin().? == 17);
    try testing.expect(heap.extractMin().? == 20);
    try testing.expect(heap.extractMin().? == 22);
    try testing.expect(heap.extractMin() == null);

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);

    try testing.expect(heap.extractMin().? == 5);
    try testing.expect(heap.extractMin().? == 10);
    try testing.expect(heap.extractMin().? == 20);
    try testing.expect(heap.extractMin() == null);
}

test "Expand capacity" {
    var heap = try BinaryHeap(i32).init(testing.allocator, 5, i32LessThan);
    defer heap.deinit();

    try heap.insert(10);
    try heap.insert(5);
    try heap.insert(20);
    try heap.insert(12);
    try heap.insert(7);
    try heap.insert(8);
    try heap.insert(17);
    try heap.insert(5);
    try heap.insert(22);

    try testing.expect(heap.extractMin().? == 5);
    try testing.expect(heap.extractMin().? == 5);
    try testing.expect(heap.extractMin().? == 7);
    try testing.expect(heap.extractMin().? == 8);
    try testing.expect(heap.extractMin().? == 10);
    try testing.expect(heap.extractMin().? == 12);
    try testing.expect(heap.extractMin().? == 17);
    try testing.expect(heap.extractMin().? == 20);
    try testing.expect(heap.extractMin().? == 22);
    try testing.expect(heap.extractMin() == null);
}

const Coord = struct {
    row: i32,
    col: i32,
};

const fScoreEntry = struct {
    coord: Coord,
    score: i32,
};

fn fScoreLessThan(a: fScoreEntry, b: fScoreEntry) bool {
    return a.score < b.score;
}

test "With custom struct" {
    var heap = try BinaryHeap(fScoreEntry).initCapacity(testing.allocator, 5, fScoreLessThan);
    defer heap.deinit();

    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 10 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 5 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 20 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 25 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 12 });
    try heap.insert(fScoreEntry{ .coord = Coord{ .row = 0, .col = 0 }, .score = 8 });

    try testing.expect(heap.extractMin().?.score == 5);
    try testing.expect(heap.extractMin().?.score == 8);
}
