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

    if (args.len < 2) {
        std.debug.print("Usage: {any} <file_path>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const file_path = args[1];

    const maze = try loadMaze(allocator, file_path);
    defer freeGrid(allocator, maze);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Poop {} ns\n", .{maze.len});

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

        const mapGridWidth = (mapEndX - mapStartX + 1) / maze[0].len;
        const mapGridHeight = (mapEndY - mapStartY) / maze.len;

        for (maze, 0..) |row, rowIdx| {
            for (row, 0..) |cell, colIdx| {
                const x: i32 = @intCast(mapStartX + colIdx * mapGridWidth);
                const y: i32 = @intCast(mapStartY + rowIdx * mapGridHeight);
                const width: i32 = @intCast(mapGridWidth);
                const height: i32 = @intCast(mapGridHeight);

                if (cell) {
                    rl.drawRectangle(x, y, width, height, rl.Color.black);
                } else {
                    rl.drawRectangle(x, y, width, height, rl.Color.white);
                }
            }
        }

        //----------------------------------------------------------------------------------
    }
}
