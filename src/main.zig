const rl = @import("raylib");
const std = @import("std");
const queue = @import("queue");

const MazeErrorSet = error{
    InvalidMaze,
    OutOfMemory,
};

const StackCandidates = struct {
    candidates: std.ArrayList(Coord),

    const Self = @This();

    fn init(allocator: std.mem.Allocator, initialCapacity: usize) MazeErrorSet!StackCandidates {
        return StackCandidates{
            .candidates = try std.ArrayList(Coord).initCapacity(allocator, initialCapacity),
        };
    }

    fn deinit(self: *Self) void {
        self.candidates.deinit();
    }

    fn add_candidate(self: *Self, candidate: Coord) MazeErrorSet!void {
        try self.candidates.append(candidate);
    }

    fn get_candidate(self: *Self) ?Coord {
        return self.candidates.popOrNull();
    }
};

const QueueCandidates = struct {
    candidates: queue.Queue(Coord),

    const Self = @This();

    fn init(allocator: std.mem.Allocator, initialCapacity: usize) MazeErrorSet!QueueCandidates {
        const c = try queue.Queue(Coord).init(allocator, initialCapacity);
        return QueueCandidates{ .candidates = c };
    }

    fn deinit(self: *Self) void {
        self.candidates.deinit();
    }

    fn add_candidate(self: *Self, candidate: Coord) MazeErrorSet!void {
        try self.candidates.enqueue(candidate);
    }

    fn get_candidate(self: *QueueCandidates) ?Coord {
        return self.candidates.dequeue();
    }
};

const Candidates = union(enum) {
    stackCandidates: StackCandidates,
    queueCandidates: QueueCandidates,

    pub fn add_candidate(self: *Candidates, candidate: Coord) MazeErrorSet!void {
        return switch (self.*) {
            inline else => |*case| return try case.add_candidate(candidate),
        };
    }

    pub fn get_candidate(self: *Candidates) ?Coord {
        return switch (self.*) {
            inline else => |*case| return case.get_candidate(),
        };
    }
};

fn loadFileToString(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // Read the entire file into a string
    const file_size = try file.getEndPos();
    const file_content = try file.readToEndAlloc(allocator, file_size);
    return file_content;
}

fn parseMaze(allocator: std.mem.Allocator, input: []const u8) MazeErrorSet![][]bool {
    // Split the input into lines
    var lines = std.mem.split(u8, input, "\n");
    // Count the number of lines and the row length
    var row_count: usize = 0;
    var col_count: usize = 0;
    while (lines.next()) |line| {
        if (line.len > 0) {
            row_count += 1;
            if (col_count == 0) {
                col_count = line.len;
            } else if (col_count != line.len) {
                return MazeErrorSet.InvalidMaze;
            }
        }
    }

    // Allocate the 2D array
    var grid = allocator.alloc([]bool, row_count) catch return MazeErrorSet.OutOfMemory;
    for (grid) |*row| {
        row.* = allocator.alloc(bool, col_count) catch return MazeErrorSet.OutOfMemory;
    }

    // Reset the iterator and parse the grid
    lines = std.mem.split(u8, input, "\n");
    var row: usize = 0;
    while (lines.next()) |line| : (row += 1) {
        if (line.len > 0) {
            for (line, 0..) |char, col| {
                grid[row][col] = switch (char) {
                    '.' => false,
                    '#' => true,
                    else => return MazeErrorSet.InvalidMaze,
                };
            }
        }
    }

    return grid;
}

fn freeGrid(allocator: std.mem.Allocator, grid: [][]bool) void {
    for (grid) |row| {
        allocator.free(row);
    }
    allocator.free(grid);
}

pub fn loadMaze(allocator: std.mem.Allocator, file_path: []const u8) ![][]bool {
    const str = try loadFileToString(allocator, file_path);
    defer allocator.free(str);
    const grid = try parseMaze(allocator, str);
    return grid;
}

const Coord = struct {
    row: i32,
    col: i32,
    pub fn equals(self: Coord, other: Coord) bool {
        return self.row == other.row and self.col == other.col;
    }
};

const Visit = enum {
    Empty, // Unvisited and unimpeaded
    Visited, // Checked for goal
    Candidate, // Added to consider later
    Blocked, // Wall
};

pub fn makeVisited(allocator: std.mem.Allocator, maze: []const []const bool) ![][]Visit {
    // Allocate the outer slice for rows
    var visited = try allocator.alloc([]Visit, maze.len);
    errdefer allocator.free(visited);

    // Allocate each row and initialize it
    for (visited, 0..) |*row, rowIdx| {
        row.* = try allocator.alloc(Visit, maze[rowIdx].len);
        errdefer {
            // Free all previously allocated rows if an error occurs
            for (visited[0..rowIdx]) |r| {
                allocator.free(r);
            }
            allocator.free(visited);
        }
    }

    // Populate the `visited` array based on the `maze`
    for (maze, 0..) |row, rowIdx| {
        for (row, 0..) |cell, colIdx| {
            visited[rowIdx][colIdx] = if (cell) Visit.Blocked else Visit.Empty;
        }
    }

    return visited;
}

pub fn getEmptyNeighbors(allocator: std.mem.Allocator, visited: []const []const Visit, current: Coord) ![]Coord {
    var neighbors = std.ArrayList(Coord).init(allocator);
    errdefer neighbors.deinit(); // Ensure cleanup on error

    // Check the cell above
    if (current.row > 0 and visited[@intCast(current.row - 1)][@intCast(current.col)] == Visit.Empty) {
        try neighbors.append(Coord{ .row = current.row - 1, .col = current.col });
    }

    // Check the cell below
    if (current.row + 1 < visited.len and visited[@intCast(current.row + 1)][@intCast(current.col)] == Visit.Empty) {
        try neighbors.append(Coord{ .row = current.row + 1, .col = current.col });
    }

    // Check the cell to the left
    if (current.col > 0 and visited[@intCast(current.row)][@intCast(current.col - 1)] == Visit.Empty) {
        try neighbors.append(Coord{ .row = current.row, .col = current.col - 1 });
    }

    // Check the cell to the right
    if (current.col + 1 < visited[0].len and visited[@intCast(current.row)][@intCast(current.col + 1)] == Visit.Empty) {
        try neighbors.append(Coord{ .row = current.row, .col = current.col + 1 });
    }

    return neighbors.toOwnedSlice();
}

pub fn freeVisited(allocator: std.mem.Allocator, visited: [][]Visit) void {
    for (visited) |row| {
        allocator.free(row);
    }
    allocator.free(visited);
}

const SearchType = enum {
    DepthFirst,
    BreadthFirst,
};

pub fn parseSearchType(search_type: []const u8) !SearchType {
    if (std.mem.eql(u8, search_type, "depthfirst")) {
        return SearchType.DepthFirst;
    } else if (std.mem.eql(u8, search_type, "breadthfirst")) {
        return SearchType.BreadthFirst;
    } else {
        return error.InvalidArguments;
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 7) {
        std.debug.print("Usage: {any} <file_path> <start_row> <start_col> <end_row> <end_col> <search_type (depthfirst, breadthfirst)>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const file_path = args[1];
    const start_row = try std.fmt.parseInt(usize, args[2], 10);
    const start_col = try std.fmt.parseInt(usize, args[3], 10);
    const end_row = try std.fmt.parseInt(usize, args[4], 10);
    const end_col = try std.fmt.parseInt(usize, args[5], 10);
    const searchType = try parseSearchType(args[6]);

    const maze: [][]bool = try loadMaze(allocator, file_path);
    defer freeGrid(allocator, maze);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Maze loaded with {} rows\n", .{maze.len});

    // Initialization
    //--------------------------------------------------------------------------------------
    const windowWidth = 1200;
    const windowHeight = 900;
    const leftMargin = 20;
    const topMargin = 20;
    const rightMargin = 20;
    const bottomMargin = 20;

    rl.initWindow(windowWidth, windowHeight, "Grid search in Zig");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);

    //--------------------------------------------------------------------------------------

    // Method
    // current_row and current_col set to start position
    // while current_row and current_col are not equal to end position
    //   expand empty neighbors
    //     this is done up down left then right and appended
    //     so candidates will be in right, left, down and up
    //   add empty neighbors to stack
    //     they are added in order but to the stack so we should expect the priority
    //     to be in the reverse order when popped
    //     ie up down left right
    //   pop stack as current row and column
    // Data
    //   Need a struct to hold row and col
    //   Stack of coord
    //   array of visited data

    // data
    //   current position
    //   target position
    //   visited array
    //   candidates
    // operations
    //   add a candidate to candidates
    //   advance the search one step
    //     get the next candidate
    //     access to visited array (not an operation)

    var current: ?Coord = Coord{ .row = @intCast(start_row), .col = @intCast(start_col) };
    const target = Coord{ .row = @intCast(end_row), .col = @intCast(end_col) };

    var visited: [][]Visit = try makeVisited(allocator, maze);
    defer freeVisited(allocator, visited);

    const sc = try StackCandidates.init(allocator, maze.len * maze[0].len);
    const qc = try QueueCandidates.init(allocator, maze.len * maze[0].len);

    var candidates: Candidates = switch (searchType) {
        SearchType.DepthFirst => Candidates{ .stackCandidates = sc },
        SearchType.BreadthFirst => Candidates{ .queueCandidates = qc },
    };

    // var candidates = try queue.Queue(Coord).init(allocator, maze.len * maze[0].len);
    // defer candidates.deinit();

    try candidates.add_candidate(current.?);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update

        // Expand the path search if its not over already
        if (!current.?.equals(target)) {
            current = candidates.get_candidate();
            if (current) |c| {
                visited[@intCast(c.row)][@intCast(c.col)] = Visit.Visited;
                if (!c.equals(target)) {
                    const emptyNeighbors = try getEmptyNeighbors(allocator, visited, c);
                    defer allocator.free(emptyNeighbors);

                    for (emptyNeighbors) |neighbor| {
                        visited[@intCast(neighbor.row)][@intCast(neighbor.col)] = Visit.Candidate;
                        try candidates.add_candidate(neighbor);
                    }
                }
            }
        }

        // Draw
        //----------------------------------------------------------------------------------
        const frameTime = rl.getFrameTime();

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.light_gray);

        // Display the frame time
        const searchTypeText: [*:0]const u8 = switch (searchType) {
            SearchType.DepthFirst => "Depth First",
            SearchType.BreadthFirst => "Breadth First",
        };
        const textPtr = std.mem.span(searchTypeText);
        const frameTimeText = rl.textFormat("ZigPath - Search type %s Render time: %.3f ms", .{ textPtr.ptr, frameTime * 1000 });
        rl.drawText(frameTimeText, leftMargin, rightMargin, 18, rl.Color.black);

        const mapStartY = topMargin + 30;
        const mapEndY = windowHeight - bottomMargin;

        const mapStartX = leftMargin;
        const mapEndX = windowWidth - rightMargin;

        // Calculate the maximum possible square size for the grid
        const availableWidth = mapEndX - mapStartX;
        const availableHeight = mapEndY - mapStartY;

        const maxCellSize = @min(availableWidth / maze[0].len, availableHeight / maze.len);

        // Center the grid within the available space
        const gridWidth = maxCellSize * maze[0].len;
        const gridHeight = maxCellSize * maze.len;

        const gridStartX = mapStartX + (availableWidth - gridWidth) / 2;
        const gridStartY = mapStartY + (availableHeight - gridHeight) / 2;

        for (visited, 0..) |row, rowIdx| {
            for (row, 0..) |cell, colIdx| {
                const x: i32 = @intCast(gridStartX + colIdx * maxCellSize);
                const y: i32 = @intCast(gridStartY + rowIdx * maxCellSize);
                const width: i32 = @intCast(maxCellSize);
                const height: i32 = @intCast(maxCellSize);

                // Highlight start and end positions
                if (current != null and rowIdx == current.?.row and colIdx == current.?.col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.yellow);
                } else if (rowIdx == start_row and colIdx == start_col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.green);
                } else if (rowIdx == end_row and colIdx == end_col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.red);
                } else {
                    switch (cell) {
                        Visit.Empty => rl.drawRectangle(x, y, width, height, rl.Color.white),
                        Visit.Visited => rl.drawRectangle(x, y, width, height, rl.Color.sky_blue),
                        Visit.Candidate => rl.drawRectangle(x, y, width, height, rl.Color.dark_blue),
                        Visit.Blocked => rl.drawRectangle(x, y, width, height, rl.Color.dark_gray),
                    }
                }
            }
        }

        //----------------------------------------------------------------------------------
    }
}
