const rl = @import("raylib");
const std = @import("std");
const maze_manifest = @import("maze_manifest");

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
    if (file_size > std.math.maxInt(usize)) return error.FileTooLarge;
    const file_content = try file.readToEndAlloc(allocator, @intCast(file_size));
    return file_content;
}

fn parseMaze(allocator: std.mem.Allocator, input: []const u8) MazeErrorSet![][]bool {
    // Split the input into lines
    rl.traceLog(rl.TraceLogLevel.info, "parseMaze", .{});
    var lines = std.mem.splitScalar(u8, input, '\n');
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
    rl.traceLog(rl.TraceLogLevel.info, "parseMaze allocate {} rows", .{row_count});
    var grid = allocator.alloc([]bool, row_count) catch return MazeErrorSet.OutOfMemory;
    rl.traceLog(rl.TraceLogLevel.info, "parseMaze allocated", .{});
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
    rl.traceLog(rl.TraceLogLevel.info, "loadMaze", .{});
    // if (std.mem.eql(u8, file_path, "/defaultmaze")) {
    //     // Use the default maze if no file path is provided
    //     const slice: []const u8 = std.mem.span(defaultMaze);
    //     return try parseMaze(allocator, slice);
    // }
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
    SelectingMaze,
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

// default maze
const defaultMaze: [*:0]const u8 =
    "....#.....\n" ++
    ".......###\n" ++
    ".......#..\n" ++
    "..######..\n" ++
    "..#....#..\n" ++
    "..#.......\n" ++
    ".##.......\n" ++
    "........#.\n" ++
    "#.........\n" ++
    "......#...\n";

pub fn main() anyerror!void {
    const allocator = rl.mem;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var file_path: []const u8 = undefined;
    if (args.len < 2) {
        file_path = ""; // Not used until a maze is selected
    } else {
        file_path = args[1];
    }
    var searchType = SearchType.AStar;

    // Defer initialization of maze-specific data
    var maze: [][]bool = &.{};
    var visited: [][]Visit = &.{};

    const stdout = std.io.getStdOut().writer();

    // --- Raylib Window Initialization ---
    rl.initWindow(1, 1, ""); // Temporary window for monitor dimensions
    const monitorWidth = rl.getMonitorWidth(0);
    const monitorHeight = rl.getMonitorHeight(0);
    rl.closeWindow();

    const targetWidth: i32 = 1600;
    const targetHeight: i32 = 900;
    const targetAspectRatio = @as(f32, @floatFromInt(targetWidth)) / @as(f32, @floatFromInt(targetHeight));

    var windowWidth = targetWidth;
    var windowHeight = targetHeight;

    if (windowWidth > monitorWidth) {
        windowWidth = @max(800, monitorWidth - 100);
        windowHeight = @intFromFloat(@as(f32, @floatFromInt(windowWidth)) / targetAspectRatio);
    }
    if (windowHeight > monitorHeight) {
        windowHeight = @max(450, monitorHeight - 100);
        windowWidth = @intFromFloat(@as(f32, @floatFromInt(windowHeight)) * targetAspectRatio);
    }

    const leftMargin = 20;
    const topMargin = 20;
    const rightMargin = 20;
    const bottomMargin = 20;
    const mapStartMargin = 90;

    rl.setConfigFlags(.{});
    rl.initWindow(windowWidth, windowHeight, "ZigPath");
    const screenWidth = rl.getMonitorWidth(0);
    const screenHeight = rl.getMonitorHeight(0);
    if (screenWidth > 0 and screenHeight > 0) {
        rl.setWindowPosition(@divFloor(screenWidth - windowWidth, 2), @divFloor(screenHeight - windowHeight, 2));
    }
    defer rl.closeWindow();

    const font = rl.loadFont("resources/TechnoRaceItalic-eZRWe.otf") catch |e| {
        std.debug.print("Failed to load font: {}\n", .{e});
        return e;
    };

    rl.setTargetFPS(60);

    // --- State and Search Data Initialization ---
    var state: State = .SelectingMaze;
    var start: ?Coord = null;
    var end: ?Coord = null;

    var cameFrom = std.AutoHashMap(Coord, Coord).init(allocator);
    defer cameFrom.deinit();

    var candidates: SearchCandidates = undefined;
    var solved = false;
    var failed = false;

    var qc: BreadthFirstSearch = undefined;
    var sc: DepthFirstSearch = undefined;
    var ac: AStarSearch = undefined;

    // --- Main Game Loop ---
    while (!rl.windowShouldClose()) {
        // --- Handle Mouse Clicks ---
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            const mouseX: f32 = @floatFromInt(rl.getMouseX());
            const mouseY: f32 = @floatFromInt(rl.getMouseY());

            if (state == .SelectingMaze) {
                var buf: [64]u8 = undefined;
                const mazeListY: f32 = topMargin + 50;
                for (maze_manifest.maze_files, 0..) |maze_file, i| {
                    const maze_text_z = try std.fmt.bufPrintZ(&buf, "{s}", .{maze_file});
                    const maze_text_width = rl.measureTextEx(font, maze_text_z, 20, 2).x;
                    const maze_text_height = rl.measureTextEx(font, maze_text_z, 20, 2).y;
                    const maze_rect = rl.Rectangle{
                        .x = leftMargin,
                        .y = mazeListY + @as(f32, @floatFromInt(i)) * 30,
                        .width = maze_text_width,
                        .height = maze_text_height,
                    };

                    if (rl.checkCollisionPointRec(.{ .x = mouseX, .y = mouseY }, maze_rect)) {
                        file_path = try std.fs.path.join(allocator, &[_][]const u8{ "resources", maze_file });

                        // If a maze was already loaded, free its memory first
                        if (maze.len > 0) {
                            freeGrid(allocator, maze);
                            freeVisited(allocator, visited);
                            switch (searchType) {
                                .DepthFirst => sc.deinit(),
                                .BreadthFirst => qc.deinit(),
                                .AStar => ac.deinit(),
                            }
                        }

                        // Load new maze and initialize all related data
                        maze = try loadMaze(allocator, file_path);
                        visited = try makeVisited(allocator, maze);

                        switch (searchType) {
                            .DepthFirst => {
                                sc = try DepthFirstSearch.init(allocator, maze.len * maze[0].len);
                                candidates = SearchCandidates{ .stackCandidates = &sc };
                            },
                            .BreadthFirst => {
                                qc = try BreadthFirstSearch.init(allocator, maze.len * maze[0].len);
                                candidates = SearchCandidates{ .queueCandidates = &qc };
                            },
                            .AStar => {
                                ac = try AStarSearch.init(allocator, Coord{ .row = 0, .col = 0 }); // Target is updated later
                                candidates = SearchCandidates{ .aStarCandidates = &ac };
                            },
                        }
                        try stdout.print("Maze was loaded with {} rows\n", .{maze.len});
                        state = .SelectingStart;
                        break; // Exit the for loop once a maze is selected
                    }
                }
            } else { // Handle clicks for all other states (where maze is loaded)
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

                const prefixText = "ZigPath - Search type ";
                const fontSize = @as(f32, @floatFromInt(font.baseSize)) * 1.4;
                const spacing = 4;
                const prefixWidth = rl.measureTextEx(font, prefixText, fontSize, spacing).x;
                const searchTypeX = leftMargin + prefixWidth;
                const searchTypeText = switch (searchType) {
                    .DepthFirst => "Depth First",
                    .BreadthFirst => "Breadth First",
                    .AStar => "AStar",
                };
                const searchTypeWidth = rl.measureTextEx(font, searchTypeText, fontSize, spacing).x;
                const searchTypeHeight = rl.measureTextEx(font, searchTypeText, fontSize, spacing).y;
                const searchTypeRect = rl.Rectangle{
                    .x = searchTypeX,
                    .y = topMargin,
                    .width = searchTypeWidth,
                    .height = searchTypeHeight,
                };

                if (state == .SelectingStart and rl.checkCollisionPointRec(.{ .x = mouseX, .y = mouseY }, searchTypeRect)) {
                    const previousSearchType = searchType;
                    searchType = switch (searchType) {
                        .DepthFirst => .BreadthFirst,
                        .BreadthFirst => .AStar,
                        .AStar => .DepthFirst,
                    };
                    try resetSearchState(allocator, maze, &visited, &cameFrom, &candidates, &sc, &qc, &ac, searchType, previousSearchType);
                } else if (state == .Failed or state == .Solved) {
                    try resetSearchState(allocator, maze, &visited, &cameFrom, &candidates, &sc, &qc, &ac, searchType, searchType);
                    start = null;
                    end = null;
                    solved = false;
                    failed = false;
                    state = .SelectingStart;
                } else if (mouseX >= @as(f32, @floatFromInt(gridStartX)) and mouseX < @as(f32, @floatFromInt(gridStartX + gridWidth)) and
                    mouseY >= @as(f32, @floatFromInt(gridStartY)) and mouseY < @as(f32, @floatFromInt(gridStartY + gridHeight))) {
                    const col: i32 = @as(i32, @intFromFloat(@divFloor(mouseX - @as(f32, @floatFromInt(gridStartX)), @as(f32, @floatFromInt(maxCellSize)))));
                    const row: i32 = @as(i32, @intFromFloat(@divFloor(mouseY - @as(f32, @floatFromInt(gridStartY)), @as(f32, @floatFromInt(maxCellSize)))));

                    if (state == .SelectingStart) {
                        start = Coord{ .row = row, .col = col };
                        state = .SelectingEnd;
                    } else if (state == .SelectingEnd) {
                        end = Coord{ .row = row, .col = col };
                        state = .Running;

                        if (searchType == .AStar) {
                            ac.deinit();
                            ac = try AStarSearch.init(allocator, end.?);
                            candidates = SearchCandidates{ .aStarCandidates = &ac };
                        }
                        _ = try candidates.add_candidate(start.?, null);
                    }
                }
            }
        }

        // --- Expand Path Search ---
        if (state == .Running and !failed and !solved) {
            const current = try candidates.get_candidate();
            if (current) |c| {
                if (c.equals(end.?)) {
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

        // --- Draw ---
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.light_gray);

        if (state == .SelectingMaze) {
            const helpText = "Click on a maze to load it";
            rl.drawTextEx(font, helpText, .{ .x = leftMargin, .y = topMargin }, @as(f32, @floatFromInt(font.baseSize)) * 1.0, 2, rl.Color.black);
            var buf: [64]u8 = undefined;
            const mazeListY: f32 = topMargin + 50;
            for (maze_manifest.maze_files, 0..) |maze_file, i| {
                const maze_text_z = try std.fmt.bufPrintZ(&buf, "{s}", .{maze_file});
                rl.drawTextEx(font, maze_text_z, .{ .x = leftMargin, .y = mazeListY + @as(f32, @floatFromInt(i)) * 30 }, 20, 2, rl.Color.black);
            }
        } else { // Draw maze and UI for all other states
            const prefixText = "ZigPath - Search type ";
            const fontSize = @as(f32, @floatFromInt(font.baseSize)) * 1.4;
            const spacing = 4;
            const prefixWidth = rl.measureTextEx(font, prefixText, fontSize, spacing).x;
            const searchTypeX = leftMargin + prefixWidth;
            const searchTypeText = switch (searchType) {
                .DepthFirst => "Depth First",
                .BreadthFirst => "Breadth First",
                .AStar => "AStar",
            };
            rl.drawTextEx(font, prefixText, .{ .x = leftMargin, .y = topMargin }, fontSize, spacing, rl.Color.black);
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

                    if (start != null and rowIdx == start.?.row and colIdx == start.?.col) {
                        rl.drawRectangle(x, y, width, height, rl.Color.green);
                        rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                    } else if (end != null and rowIdx == end.?.row and colIdx == end.?.col) {
                        rl.drawRectangle(x, y, width, height, rl.Color.red);
                        rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                    } else {
                        switch (cell) {
                            .Empty => {
                                rl.drawRectangle(x, y, width, height, rl.Color.white);
                                rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                            },
                            .Visited => {
                                rl.drawRectangle(x, y, width, height, rl.Color.sky_blue);
                                rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                            },
                            .Candidate => {
                                rl.drawRectangle(x, y, width, height, rl.Color.dark_blue);
                                rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                            },
                            .Blocked => {
                                rl.drawRectangle(x, y, width, height, rl.Color.dark_gray);
                                rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                            },
                            .Path => {
                                rl.drawRectangle(x, y, width, height, rl.Color.orange);
                                rl.drawRectangleLines(x, y, width, height, rl.Color.black);
                            },
                        }
                    }
                }
            }

            const textVerticalOffset = 40;
            switch (state) {
                .SelectingMaze => {}, // Should not happen in this branch
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
    }

    // --- Cleanup ---
    // Only deinit if a maze was actually loaded
    if (maze.len > 0) {
        freeGrid(allocator, maze);
        freeVisited(allocator, visited);
        switch (searchType) {
            .DepthFirst => sc.deinit(),
            .BreadthFirst => qc.deinit(),
            .AStar => ac.deinit(),
        }
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
