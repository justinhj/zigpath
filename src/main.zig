const rl = @import("raylib");
const std = @import("std");

const queue = @import("queue");
const binaryHeap = @import("BinaryHeap");

const MazeErrorSet = error{
    InvalidMaze,
    OutOfMemory,
};

const DepthFirstSearch = struct {
    candidates: std.ArrayList(Coord),

    const Self = @This();

    fn init(allocator: std.mem.Allocator, initialCapacity: usize) MazeErrorSet!DepthFirstSearch {
        return DepthFirstSearch{
            .candidates = try std.ArrayList(Coord).initCapacity(allocator, initialCapacity),
        };
    }

    fn deinit(self: *Self) void {
        self.candidates.deinit();
    }

    fn add_candidate(self: *Self, candidate: Coord, from: ?Coord) MazeErrorSet!bool {
        _ = from;
        try self.candidates.append(candidate);
        return true;
    }

    fn get_candidate(self: *Self) MazeErrorSet!?Coord {
        return self.candidates.pop();
    }
};

const BreadthFirstSearch = struct {
    candidates: queue.Queue(Coord),

    const Self = @This();

    fn init(allocator: std.mem.Allocator, initialCapacity: usize) MazeErrorSet!BreadthFirstSearch {
        const c = try queue.Queue(Coord).init(allocator, initialCapacity);
        return BreadthFirstSearch{ .candidates = c };
    }

    fn deinit(self: *Self) void {
        self.candidates.deinit();
    }

    fn add_candidate(self: *Self, candidate: Coord, from: ?Coord) MazeErrorSet!bool {
        _ = from;
        try self.candidates.enqueue(candidate);
        return true;
    }

    fn get_candidate(self: *BreadthFirstSearch) MazeErrorSet!?Coord {
        return self.candidates.dequeue();
    }
};

const fScoreEntry = struct {
    coord: Coord,
    score: i32,
};

fn fScoreLessThan(a: fScoreEntry, b: fScoreEntry) bool {
    return a.score < b.score;
}

const AStarSearch = struct {
    openSet: std.AutoHashMap(Coord, bool),
    closedSet: std.AutoHashMap(Coord, bool),
    gScore: std.AutoHashMap(Coord, i32),
    fScore: binaryHeap.BinaryHeap(fScoreEntry),
    target: Coord,

    const Self = @This();

    fn init(allocator: std.mem.Allocator, target: Coord) MazeErrorSet!AStarSearch {
        const os = std.AutoHashMap(Coord, bool).init(allocator);
        const cs = std.AutoHashMap(Coord, bool).init(allocator);
        const gs = std.AutoHashMap(Coord, i32).init(allocator);
        const fs = try binaryHeap.BinaryHeap(fScoreEntry).initCapacity(allocator, 100, fScoreLessThan);

        return AStarSearch{
            .openSet = os,
            .closedSet = cs,
            .gScore = gs,
            .fScore = fs,
            .target = target,
        };
    }

    fn deinit(self: *Self) void {
        self.openSet.deinit();
        self.closedSet.deinit();
        self.gScore.deinit();
        self.fScore.deinit();
    }

    fn manhattanDistance(self: *Self, a: Coord, b: Coord) i32 {
        _ = self;
        return @intCast(@abs(a.row - b.row) + @abs(a.col - b.col));
    }

    // Add candidate handles adding a new candidate for the astar search by updating
    // the openSet, gScore, and fScore.
    // Since the cameFrom map is managed by the client of the Candidates struct,
    // the code returns true if it should be updated (a new best node) or false
    // otherwise.
    fn add_candidate(self: *Self, candidate: Coord, from: ?Coord) MazeErrorSet!bool {
        if (self.closedSet.contains(candidate)) {
            return false;
        }
        // When from is null it means that the candidate is the start node
        // so set the prior cost to -1.
        const priorCost: i32 = if (from) |f| self.gScore.get(f) orelse 0 else -1;
        const tentativeGScore = priorCost + 1;

        if (!self.openSet.contains(candidate)) {
            _ = try self.openSet.put(candidate, true);
        }
        const previousScore = self.gScore.get(candidate) orelse std.math.maxInt(i32);
        if (tentativeGScore >= previousScore) {
            return false;
        }
        _ = try self.gScore.put(candidate, tentativeGScore);
        const fScore = tentativeGScore + self.manhattanDistance(candidate, self.target);
        _ = try self.fScore.insert(fScoreEntry{ .coord = candidate, .score = fScore });
        return true;
    }

    fn get_candidate(self: *AStarSearch) MazeErrorSet!?Coord {
        if (self.openSet.count() > 0) {
            const bestFScore = self.fScore.extractMin();
            if (bestFScore) |entry| {
                _ = self.openSet.remove(entry.coord);
                _ = try self.closedSet.put(entry.coord, true);
                return entry.coord;
            }
        }
        return null;
    }
};
const SearchCandidates = union(enum) {
    stackCandidates: *DepthFirstSearch,
    queueCandidates: *BreadthFirstSearch,
    aStarCandidates: *AStarSearch,

    pub fn add_candidate(self: *SearchCandidates, candidate: Coord, from: ?Coord) MazeErrorSet!bool {
        return switch (self.*) {
            inline else => |*case| return try case.*.add_candidate(candidate, from),
        };
    }

    pub fn get_candidate(self: *SearchCandidates) MazeErrorSet!?Coord {
        return switch (self.*) {
            inline else => |*case| return case.*.get_candidate(),
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
    var lines = std.mem.splitScalar(u8, input, '\n');
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
    lines = std.mem.splitScalar(u8, input, '\n');
    var row: usize = 0;
    while (lines.next()) |line| : (row += 1) {
        // Trim potential carriage return characters that might be left from Windows line endings (\r\n)
        const cleaned_line = std.mem.trimRight(u8, line, "\r");
        if (cleaned_line.len > 0) {
            for (cleaned_line, 0..) |char, col| {
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
    Path, // Part of the final path
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

pub fn getEmptyNeighbors(visited: []const []const Visit, current: Coord, neighbors: *[4]Coord) usize {
    var count: usize = 0;
    // Check the cell above
    if (current.row > 0 and visited[@intCast(current.row - 1)][@intCast(current.col)] == Visit.Empty) {
        neighbors[count] = Coord{ .row = current.row - 1, .col = current.col };
        count += 1;
    }

    // Check the cell below
    if (current.row + 1 < visited.len and visited[@intCast(current.row + 1)][@intCast(current.col)] == Visit.Empty) {
        neighbors[count] = Coord{ .row = current.row + 1, .col = current.col };
        count += 1;
    }

    // Check the cell to the left
    if (current.col > 0 and visited[@intCast(current.row)][@intCast(current.col - 1)] == Visit.Empty) {
        neighbors[count] = Coord{ .row = current.row, .col = current.col - 1 };
        count += 1;
    }

    // Check the cell to the right
    if (current.col + 1 < visited[0].len and visited[@intCast(current.row)][@intCast(current.col + 1)] == Visit.Empty) {
        neighbors[count] = Coord{ .row = current.row, .col = current.col + 1 };
        count += 1;
    }

    return count;
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
    AStar,
};

pub fn parseSearchType(search_type: []const u8) !SearchType {
    if (std.mem.eql(u8, search_type, "depthfirst")) {
        return SearchType.DepthFirst;
    } else if (std.mem.eql(u8, search_type, "breadthfirst")) {
        return SearchType.BreadthFirst;
    } else if (std.mem.eql(u8, search_type, "astar")) {
        return SearchType.AStar;
    } else {
        return error.InvalidArguments;
    }
}

const State = enum {
    SelectingStart,
    SelectingEnd,
    Running,
    Solved,
    Failed,
};

pub fn resetSearchState(allocator: std.mem.Allocator, maze: []const []const bool, visited: *[][]Visit, cameFrom: *std.AutoHashMap(Coord, Coord), candidates: *SearchCandidates, sc: *DepthFirstSearch, qc: *BreadthFirstSearch, ac: *AStarSearch, searchType: SearchType, previousSearchType: SearchType) !void {
    // Free and recreate visited array
    freeVisited(allocator, visited.*);
    visited.* = try makeVisited(allocator, maze);

    // Clear cameFrom map
    cameFrom.clearAndFree();

    // Deinit previous candidates and create new ones
    switch (previousSearchType) {
        SearchType.DepthFirst => sc.deinit(),
        SearchType.BreadthFirst => qc.deinit(),
        SearchType.AStar => ac.deinit(),
    }

    // Reinitialize candidates based on search type
    switch (searchType) {
        SearchType.DepthFirst => {
            sc.* = try DepthFirstSearch.init(allocator, maze.len * maze[0].len);
            candidates.* = SearchCandidates{ .stackCandidates = sc };
        },
        SearchType.BreadthFirst => {
            qc.* = try BreadthFirstSearch.init(allocator, maze.len * maze[0].len);
            candidates.* = SearchCandidates{ .queueCandidates = qc };
        },
        SearchType.AStar => {
            // Note: AStarSearch will be reinitialized with proper end coord when needed
            ac.* = try AStarSearch.init(allocator, Coord{ .row = 0, .col = 0 });
            candidates.* = SearchCandidates{ .aStarCandidates = ac };
        },
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 1) {
        std.debug.print("Usage: {d} args provided. Expected maze <file_path>\n", .{args.len});
        return error.InvalidArguments;
    }

    const file_path = args[1];
    var searchType = SearchType.AStar;

    const maze: [][]bool = try loadMaze(allocator, file_path);
    defer freeGrid(allocator, maze);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Maze was loaded with {} rows\n", .{maze.len});

    // Unfortunately, raylib requires a window to be initialized before we can get monitor dimensions.
    rl.initWindow(1, 1, "");
    const monitorWidth = rl.getMonitorWidth(0); // 0 is the primary monitor
    const monitorHeight = rl.getMonitorHeight(0);

    rl.closeWindow();

    // Define the desired window size and aspect ratio
    const targetWidth: i32 = 1600;
    const targetHeight: i32 = 900;
    const targetAspectRatio = @as(f32, @floatFromInt(targetWidth)) / @as(f32, @floatFromInt(targetHeight));

    // Calculate maximum possible window size that fits the screen
    var windowWidth = targetWidth;
    var windowHeight = targetHeight;

    // If window is too wide for the screen, scale it down
    if (windowWidth > monitorWidth) {
        windowWidth = @max(800, monitorWidth - 100); // Leave some margin
        windowHeight = @intFromFloat(@as(f32, @floatFromInt(windowWidth)) / targetAspectRatio);

        // If the scaled height is still too tall, scale down further
        if (windowHeight > monitorHeight) {
            windowHeight = @max(450, monitorHeight - 100);
            windowWidth = @intFromFloat(@as(f32, @floatFromInt(windowHeight)) * targetAspectRatio);
        }
    }
    const leftMargin = 20;
    const topMargin = 20;
    const rightMargin = 20;
    const bottomMargin = 20;
    const mapStartMargin = 90;

    // Set window state before creating the window to avoid flickering
    rl.setConfigFlags(.{});

    // Initialize the window with the calculated dimensions
    rl.initWindow(windowWidth, windowHeight, "ZigPath");

    // Center the window on the screen
    const screenWidth = rl.getMonitorWidth(0);
    const screenHeight = rl.getMonitorHeight(0);
    if (screenWidth > 0 and screenHeight > 0) {
        rl.setWindowPosition(@divFloor(screenWidth - windowWidth, 2), @divFloor(screenHeight - windowHeight, 2));
    }
    defer rl.closeWindow();

    const font = try rl.loadFont("data/TechnoRaceItalic-eZRWe.otf");

    rl.setTargetFPS(60);

    var state: State = .SelectingStart;
    var start: ?Coord = null;
    var end: ?Coord = null;

    var visited: [][]Visit = try makeVisited(allocator, maze);
    defer freeVisited(allocator, visited);

    var cameFrom = std.AutoHashMap(Coord, Coord).init(allocator);
    defer cameFrom.deinit();

    var candidates: SearchCandidates = undefined;

    var solved = false;
    var failed = false;

    var qc: BreadthFirstSearch = undefined;
    var sc: DepthFirstSearch = undefined;
    var ac: AStarSearch = undefined;

    // Initialize candidates based on search type
    switch (searchType) {
        SearchType.DepthFirst => {
            sc = try DepthFirstSearch.init(allocator, maze.len * maze[0].len);
            candidates = SearchCandidates{ .stackCandidates = &sc };
        },
        SearchType.BreadthFirst => {
            qc = try BreadthFirstSearch.init(allocator, maze.len * maze[0].len);
            candidates = SearchCandidates{ .queueCandidates = &qc };
        },
        SearchType.AStar => {
            ac = try AStarSearch.init(allocator, Coord{ .row = 0, .col = 0 });
            candidates = SearchCandidates{ .aStarCandidates = &ac };
        },
    }

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Calculate search type display area
        const prefixText = "ZigPath - Search type ";
        const fontSize = @as(f32, @floatFromInt(font.baseSize)) * 1.4;
        const spacing = 4;
        const prefixWidth = rl.measureTextEx(font, prefixText, fontSize, spacing).x;
        const searchTypeX = leftMargin + prefixWidth;
        const searchTypeText = switch (searchType) {
            SearchType.DepthFirst => "Depth First",
            SearchType.BreadthFirst => "Breadth First",
            SearchType.AStar => "AStar",
        };
        const searchTypeWidth = rl.measureTextEx(font, searchTypeText, fontSize, spacing).x;
        const searchTypeHeight = rl.measureTextEx(font, searchTypeText, fontSize, spacing).y;
        const searchTypeRect = rl.Rectangle{
            .x = searchTypeX,
            .y = topMargin,
            .width = searchTypeWidth,
            .height = searchTypeHeight,
        };

        // Handle mouse clicks
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            const mouseX: f32 = @floatFromInt(rl.getMouseX());
            const mouseY: f32 = @floatFromInt(rl.getMouseY());

            const mapStartY = topMargin + mapStartMargin;
            const mapEndY = windowHeight - bottomMargin;
            const mapStartX = leftMargin;
            const mapEndX = windowWidth - rightMargin;
            const availableWidth = mapEndX - mapStartX;
            const availableHeight = mapEndY - mapStartY;
            const maxCellSize = @min(@divFloor(availableWidth, @as(i32, @intCast(maze[0].len))), @divFloor(availableHeight, @as(i32, @intCast(maze.len))));
            const gridWidth = maxCellSize * @as(i32, @intCast(maze[0].len));
            const gridHeight = maxCellSize * @as(i32, @intCast(maze.len));
            const gridStartX = mapStartX + @divFloor(availableWidth - gridWidth, 2);
            const gridStartY = mapStartY + @divFloor(availableHeight - gridHeight, 2);

            // Check if click is on search type text during SelectingStart
            if (state == .SelectingStart and rl.checkCollisionPointRec(.{ .x = mouseX, .y = mouseY }, searchTypeRect)) {
                // Cycle to next search type
                const previousSearchType = searchType;
                searchType = switch (searchType) {
                    .DepthFirst => .BreadthFirst,
                    .BreadthFirst => .AStar,
                    .AStar => .DepthFirst,
                };
                // Reset candidates with new search type
                try resetSearchState(allocator, maze, &visited, &cameFrom, &candidates, &sc, &qc, &ac, searchType, previousSearchType);
            }
            // Handle a click anywhere when in Failed or Succeeded states
            else if (state == .Failed or state == .Solved) {
                // Reset the search state and return to SelectingStart
                try resetSearchState(allocator, maze, &visited, &cameFrom, &candidates, &sc, &qc, &ac, searchType, searchType);
                start = null;
                end = null;
                solved = false;
                failed = false;
                state = .SelectingStart;
            }
            // Handle clicks on the maze
            else if (mouseX >= @as(f32, @floatFromInt(gridStartX)) and mouseX < @as(f32, @floatFromInt(gridStartX + gridWidth)) and
                mouseY >= @as(f32, @floatFromInt(gridStartY)) and mouseY < @as(f32, @floatFromInt(gridStartY + gridHeight)))
            {
                const col: i32 = @as(i32, @intFromFloat(@divFloor(mouseX - @as(f32, @floatFromInt(gridStartX)), @as(f32, @floatFromInt(maxCellSize)))));
                const row: i32 = @as(i32, @intFromFloat(@divFloor(mouseY - @as(f32, @floatFromInt(gridStartY)), @as(f32, @floatFromInt(maxCellSize)))));

                if (state == .SelectingStart) {
                    start = Coord{ .row = row, .col = col };
                    state = .SelectingEnd;
                } else if (state == .SelectingEnd) {
                    end = Coord{ .row = row, .col = col };
                    state = .Running;

                    // Reinitialize AStar with proper end coordinate
                    if (searchType == .AStar) {
                        ac.deinit();
                        ac = try AStarSearch.init(allocator, end.?);
                        candidates = SearchCandidates{ .aStarCandidates = &ac };
                    }

                    _ = try candidates.add_candidate(start.?, null);
                } else {
                    std.debug.assert(state == .Running);
                }
            }
        }

        // Expand the path search if it's not over already
        if (state == .Running and !failed and !solved) {
            const current = try candidates.get_candidate();
            if (current) |c| {
                if (c.equals(end.?)) {
                    // Construct the path
                    var path = std.ArrayList(Coord).init(allocator);
                    defer path.deinit();

                    var currentPath: ?Coord = end.?;
                    while (currentPath != null) {
                        try path.append(currentPath.?);
                        currentPath = cameFrom.get(currentPath.?);
                    }

                    for (path.items) |coord| {
                        visited[@intCast(coord.row)][@intCast(coord.col)] = Visit.Path;
                    }

                    solved = true;
                    state = .Solved;
                } else {
                    visited[@intCast(c.row)][@intCast(c.col)] = Visit.Visited;
                    if (!c.equals(end.?)) {
                        var neighbors: [4]Coord = undefined;
                        const emptyNeighbors = getEmptyNeighbors(visited, c, &neighbors);

                        for (0..emptyNeighbors) |n| {
                            visited[@intCast(neighbors[n].row)][@intCast(neighbors[n].col)] = Visit.Candidate;
                            const newBest = try candidates.add_candidate(neighbors[n], current);
                            if (newBest) {
                                try cameFrom.put(neighbors[n], c);
                            }
                        }
                    }
                }
            } else {
                failed = true;
                state = .Failed;
            }
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.light_gray);

        // Draw the prefix text in black
        rl.drawTextEx(font, prefixText, .{ .x = leftMargin, .y = topMargin }, fontSize, spacing, rl.Color.black);

        // Draw the search type text in dark grey
        rl.drawTextEx(font, searchTypeText, .{ .x = searchTypeX, .y = topMargin }, fontSize, spacing, rl.Color.dark_gray);

        const mapStartY = topMargin + mapStartMargin;
        const mapEndY = windowHeight - bottomMargin;
        const mapStartX = leftMargin;
        const mapEndX = windowWidth - rightMargin;
        const availableWidth = mapEndX - mapStartX;
        const availableHeight = mapEndY - mapStartY;
        const maxCellSize = @min(@divFloor(availableWidth, @as(i32, @intCast(maze[0].len))), @divFloor(availableHeight, @as(i32, @intCast(maze.len))));
        const gridWidth = maxCellSize * @as(i32, @intCast(maze[0].len));
        const gridHeight = maxCellSize * @as(i32, @intCast(maze.len));
        const gridStartX = mapStartX + @divFloor(availableWidth - gridWidth, 2);
        const gridStartY = mapStartY + @divFloor(availableHeight - gridHeight, 2);

        for (visited, 0..) |row, rowIdx| {
            for (row, 0..) |cell, colIdx| {
                const x = gridStartX + @as(i32, @intCast(colIdx)) * maxCellSize;
                const y = gridStartY + @as(i32, @intCast(rowIdx)) * maxCellSize;
                const width = maxCellSize;
                const height = maxCellSize;

                // Highlight start and end positions
                if (start != null and rowIdx == start.?.row and colIdx == start.?.col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.green);
                    rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                } else if (end != null and rowIdx == end.?.row and colIdx == end.?.col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.red);
                    rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                } else {
                    switch (cell) {
                        Visit.Empty => {
                            rl.drawRectangle(x, y, width, height, rl.Color.white);
                            rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                        },
                        Visit.Visited => {
                            rl.drawRectangle(x, y, width, height, rl.Color.sky_blue);
                            rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                        },
                        Visit.Candidate => {
                            rl.drawRectangle(x, y, width, height, rl.Color.dark_blue);
                            rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                        },
                        Visit.Blocked => {
                            rl.drawRectangle(x, y, width, height, rl.Color.dark_gray);
                            rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                        },
                        Visit.Path => {
                            rl.drawRectangle(x, y, width, height, rl.Color.orange);
                            rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                        },
                    }
                }
            }
        }

        const textVerticalOffset = 40;
        // Display help text based on the current state
        switch (state) {
            .SelectingStart => {
                const helpText = "Click on the grid to select the start cell or click search type to change";
                rl.drawTextEx(font, helpText, .{ .x = leftMargin, .y = topMargin + textVerticalOffset }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            },
            .SelectingEnd => {
                const helpText = "Click on the grid to select the end cell";
                rl.drawTextEx(font, helpText, .{ .x = leftMargin, .y = topMargin + textVerticalOffset }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            },
            .Running => {
                const statusText = "Searching for path...";
                rl.drawTextEx(font, statusText, .{ .x = leftMargin, .y = topMargin + textVerticalOffset }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            },
            .Solved => {
                const statusText = "Path found! Click to restart.";
                rl.drawTextEx(font, statusText, .{ .x = leftMargin, .y = topMargin + textVerticalOffset }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            },
            .Failed => {
                const statusText = "No path found! Click to restart.";
                rl.drawTextEx(font, statusText, .{ .x = leftMargin, .y = topMargin + textVerticalOffset }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            },
        }
    }

    // Cleanup
    switch (searchType) {
        SearchType.DepthFirst => sc.deinit(),
        SearchType.BreadthFirst => qc.deinit(),
        SearchType.AStar => ac.deinit(),
    }
}

// ... [Rest of the code remains unchanged] ...

const testing = std.testing;

test "AStar search" {
    const target = Coord{ .row = 0, .col = 0 };
    var ac = try AStarSearch.init(testing.allocator, target);
    defer ac.deinit();

    _ = try ac.add_candidate(Coord{ .row = 0, .col = 1 }, null);
    _ = try ac.add_candidate(Coord{ .row = 0, .col = 1 }, null);
    _ = try ac.add_candidate(Coord{ .row = 0, .col = 1 }, null);
    _ = try ac.add_candidate(Coord{ .row = 0, .col = 1 }, null);
    const c = try ac.get_candidate();
    try testing.expectEqual(c.?.row, 0);
}
