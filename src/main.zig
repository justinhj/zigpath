const rl = @import("raylib");
const std = @import("std");

const MazeErrorSet = error{
    InvalidMaze,
    OutOfMemory,
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

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 6) {
        std.debug.print("Usage: {any} <file_path> <start_row> <start_col> <end_row> <end_col>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const file_path = args[1];
    const start_row = try std.fmt.parseInt(usize, args[2], 10);
    const start_col = try std.fmt.parseInt(usize, args[3], 10);
    const end_row = try std.fmt.parseInt(usize, args[4], 10);
    const end_col = try std.fmt.parseInt(usize, args[5], 10);

    const maze = try loadMaze(allocator, file_path);
    defer freeGrid(allocator, maze);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Maze loaded with {} rows\n", .{maze.len});

    // Initialization
    //--------------------------------------------------------------------------------------
    const windowWidth = 800;
    const windowHeight = 600;
    const leftMargin = 20;
    const topMargin = 20;
    const rightMargin = 20;
    const bottomMargin = 20;

    rl.initWindow(windowWidth, windowHeight, "Grid search in Zig");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60);
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.light_gray);

        rl.drawText("ZigPath", leftMargin, topMargin, 18, rl.Color.black);

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

        for (maze, 0..) |row, rowIdx| {
            for (row, 0..) |cell, colIdx| {
                const x: i32 = @intCast(gridStartX + colIdx * maxCellSize);
                const y: i32 = @intCast(gridStartY + rowIdx * maxCellSize);
                const width: i32 = @intCast(maxCellSize);
                const height: i32 = @intCast(maxCellSize);

                if (cell) {
                    rl.drawRectangle(x, y, width, height, rl.Color.dark_gray);
                } else {
                    rl.drawRectangle(x, y, width, height, rl.Color.white);
                }

                // Highlight start and end positions
                if (rowIdx == start_row and colIdx == start_col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.green);
                } else if (rowIdx == end_row and colIdx == end_col) {
                    rl.drawRectangle(x, y, width, height, rl.Color.red);
                }
            }
        }

        //----------------------------------------------------------------------------------
    }
}
